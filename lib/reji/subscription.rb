# frozen_string_literal: true

module Reji
  class Subscription < ActiveRecord::Base
    include Reji::InteractsWithPaymentBehavior
    include Reji::Prorates

    has_many :items, class_name: 'SubscriptionItem'
    belongs_to :owner, class_name: Reji.configuration.model, foreign_key: Reji.configuration.model_id

    scope :incomplete, -> { where(stripe_status: 'incomplete') }
    scope :past_due, -> { where(stripe_status: 'past_due') }
    scope :active, -> {
      query = (where(ends_at: nil).or(on_grace_period))
        .where('stripe_status != ?', 'incomplete')
        .where('stripe_status != ?', 'incomplete_expired')
        .where('stripe_status != ?', 'unpaid')

      query.where('stripe_status != ?', 'past_due') if Reji.deactivate_past_due

      query
    }
    scope :recurring, -> { not_on_trial.not_cancelled }
    scope :cancelled, -> { where.not(ends_at: nil) }
    scope :not_cancelled, -> { where(ends_at: nil) }
    scope :ended, -> { cancelled.not_on_grace_period }
    scope :on_trial, -> { where.not(trial_ends_at: nil).where('trial_ends_at > ?', Time.now) }
    scope :not_on_trial, -> { where(trial_ends_at: nil).or(where('trial_ends_at <= ?', Time.now)) }
    scope :on_grace_period, -> { where.not(ends_at: nil).where('ends_at > ?', Time.now) }
    scope :not_on_grace_period, -> { where(ends_at: nil).or(where('ends_at <= ?', Time.now)) }

    # The date on which the billing cycle should be anchored.
    @billing_cycle_anchor = nil

    # Get the user that owns the subscription.
    def user
      self.owner
    end

    # Determine if the subscription has multiple plans.
    def has_multiple_plans
      self.stripe_plan.nil?
    end

    # Determine if the subscription has a single plan.
    def has_single_plan
      ! self.has_multiple_plans
    end

    # Determine if the subscription has a specific plan.
    def has_plan(plan)
      return self.items.any? { |item| item.stripe_plan == plan } if self.has_multiple_plans

      self.stripe_plan == plan
    end

    # Get the subscription item for the given plan.
    def find_item_or_fail(plan)
      self.items.where(stripe_plan: plan).first
    end

    # Determine if the subscription is active, on trial, or within its grace period.
    def valid
      self.active || self.on_trial || self.on_grace_period
    end

    # Determine if the subscription is incomplete.
    def incomplete
      self.stripe_status == 'incomplete'
    end

    # Determine if the subscription is past due.
    def past_due
      self.stripe_status == 'past_due'
    end

    # Determine if the subscription is active.
    def active
      (self.ends_at.nil? || self.on_grace_period) &&
      self.stripe_status != 'incomplete' &&
      self.stripe_status != 'incomplete_expired' &&
      self.stripe_status != 'unpaid' &&
      (! Reji.deactivate_past_due || self.stripe_status != 'past_due')
    end

    # Sync the Stripe status of the subscription.
    def sync_stripe_status
      subscription = self.as_stripe_subscription

      self.update({stripe_status: subscription.status})
    end

    # Determine if the subscription is recurring and not on trial.
    def recurring
      ! self.on_trial && ! self.cancelled
    end

    # Determine if the subscription is no longer active.
    def cancelled
      ! self.ends_at.nil?
    end

    # Determine if the subscription has ended and the grace period has expired.
    def ended
      !! (self.cancelled && ! self.on_grace_period)
    end

    # Determine if the subscription is within its trial period.
    def on_trial
      !! (self.trial_ends_at && self.trial_ends_at.future?)
    end

    # Determine if the subscription is within its grace period after cancellation.
    def on_grace_period
      !! (self.ends_at && self.ends_at.future?)
    end

    # Increment the quantity of the subscription.
    def increment_quantity(count = 1, plan = nil)
      self.guard_against_incomplete

      if plan
        self.find_item_or_fail(plan)
          .set_proration_behavior(self.prorate_behavior)
          .increment_quantity(count)

        return self
      end

      self.guard_against_multiple_plans

      self.update_quantity(self.quantity + count, plan)
    end

    # Increment the quantity of the subscription, and invoice immediately.
    def increment_and_invoice(count = 1, plan = nil)
      self.guard_against_incomplete

      self.always_invoice

      if plan
        self.find_item_or_fail(plan)
          .set_proration_behavior(self.prorate_behavior)
          .increment_quantity(count)

        return self
      end

      self.guard_against_multiple_plans

      self.increment_quantity(count, plan)
    end

    # Decrement the quantity of the subscription.
    def decrement_quantity(count = 1, plan = nil)
      self.guard_against_incomplete

      if plan
        self.find_item_or_fail(plan)
          .set_proration_behavior(self.prorate_behavior)
          .decrement_quantity(count)

        return self
      end

      self.guard_against_multiple_plans

      self.update_quantity([1, self.quantity - count].max, plan)
    end

    # Update the quantity of the subscription.
    def update_quantity(quantity, plan = nil)
      self.guard_against_incomplete

      if plan
        self.find_item_or_fail(plan)
          .set_proration_behavior(self.prorate_behavior)
          .update_quantity(quantity)

        return self
      end

      self.guard_against_multiple_plans

      stripe_subscription = self.as_stripe_subscription
      stripe_subscription.quantity = quantity
      stripe_subscription.payment_behavior = self.payment_behavior
      stripe_subscription.proration_behavior = self.prorate_behavior
      stripe_subscription.save

      self.update(quantity: quantity)

      self
    end

    # Change the billing cycle anchor on a plan change.
    def anchor_billing_cycle_on(date = 'now')
      @billing_cycle_anchor = date

      self
    end

    # Force the trial to end immediately.
    def skip_trial
      self.trial_ends_at = nil

      self
    end

    # Extend an existing subscription's trial period.
    def extend_trial(date)
      raise ArgumentError.new("Extending a subscription's trial requires a date in the future.") unless date.future?

      subscription = self.as_stripe_subscription
      subscription.trial_end = date.to_i
      subscription.save

      self.update(trial_ends_at: date)

      self
    end

    # Swap the subscription to new Stripe plans.
    def swap(plans, options = {})
      plans = [plans] unless plans.instance_of? Array

      raise ArgumentError.new('Please provide at least one plan when swapping.') if plans.empty?

      self.guard_against_incomplete

      items = self.merge_items_that_should_be_deleted_during_swap(
        self.parse_swap_plans(plans)
      )

      stripe_subscription = Stripe::Subscription::update(
        self.stripe_id,
        self.get_swap_options(items, options),
        self.owner.stripe_options
      )

      self.update({
        :stripe_status => stripe_subscription.status,
        :stripe_plan => stripe_subscription.plan ? stripe_subscription.plan.id : nil,
        :quantity => stripe_subscription.quantity,
        :ends_at => nil,
      })

      stripe_subscription.items.each do |item|
        self.items.find_or_create_by(stripe_id: item.id) do |subscription_item|
          subscription_item.stripe_plan = item.plan.id
          subscription_item.quantity = item.quantity
        end
      end

      # Delete items that aren't attached to the subscription anymore...
      self.items.where('stripe_plan NOT IN (?)', items.values.pluck(:plan).compact).destroy_all

      if self.has_incomplete_payment
        Payment.new(stripe_subscription.latest_invoice.payment_intent).validate
      end

      self
    end

    # Swap the subscription to new Stripe plans, and invoice immediately.
    def swap_and_invoice(plans, options = {})
      self.always_invoice

      self.swap(plans, options)
    end

    # Add a new Stripe plan to the subscription.
    def add_plan(plan, quantity = 1, options = {})
      self.guard_against_incomplete

      if self.items.any? { |item| item.stripe_plan == plan }
        raise Reji::SubscriptionUpdateFailureError::duplicate_plan(self, plan)
      end

      subscription = self.as_stripe_subscription

      item = subscription.items.create({
        :plan => plan,
        :quantity => quantity,
        :tax_rates => self.get_plan_tax_rates_for_payload(plan),
        :payment_behavior => self.payment_behavior,
        :proration_behavior => self.prorate_behavior,
      }.merge(options))

      self.items.create({
        :stripe_id => item.id,
        :stripe_plan => plan,
        :quantity => quantity
      })

      if self.has_single_plan
        self.update({
          :stripe_plan => nil,
          :quantity => nil,
        })
      end

      self
    end

    # Add a new Stripe plan to the subscription, and invoice immediately.
    def add_plan_and_invoice(plan, quantity = 1, options = {})
      self.always_invoice

      self.add_plan(plan, quantity, options)
    end

    # Remove a Stripe plan from the subscription.
    def remove_plan(plan)
      raise Reji::SubscriptionUpdateFailureError::cannot_delete_last_plan(self) if self.has_single_plan

      item = self.find_item_or_fail(plan)

      item.as_stripe_subscription_item.delete({
        :proration_behavior => self.prorate_behavior
      })

      self.items.where(stripe_plan: plan).destroy_all

      if self.items.count < 2
        item = self.items.first

        self.update({
          :stripe_plan => item.stripe_plan,
          :quantity => quantity,
        })
      end

      self
    end

    # Cancel the subscription at the end of the billing period.
    def cancel
      subscription = self.as_stripe_subscription

      subscription.cancel_at_period_end = true

      subscription = subscription.save

      self.stripe_status = subscription.status

      # If the user was on trial, we will set the grace period to end when the trial
      # would have ended. Otherwise, we'll retrieve the end of the billing period
      # period and make that the end of the grace period for this current user.
      if self.on_trial
        self.ends_at = self.trial_ends_at
      else
        self.ends_at = Time.at(subscription.current_period_end)
      end

      self.save

      self
    end

    # Cancel the subscription immediately.
    def cancel_now
      self.as_stripe_subscription.cancel({
        :prorate => self.prorate_behavior == 'create_prorations',
      })

      self.mark_as_cancelled

      self
    end

    # Cancel the subscription and invoice immediately.
    def cancel_now_and_invoice
      self.as_stripe_subscription.cancel({
        :invoice_now => true,
        :prorate => self.prorate_behavior == 'create_prorations',
      })

      self.mark_as_cancelled

      self
    end

    # Mark the subscription as cancelled.
    def mark_as_cancelled
      self.update({
        :stripe_status => 'canceled',
        :ends_at => Time.now,
      })
    end

    # Resume the cancelled subscription.
    def resume
      raise ArgumentError.new('Unable to resume subscription that is not within grace period.') unless self.on_grace_period

      subscription = self.as_stripe_subscription

      subscription.cancel_at_period_end = false

      if self.on_trial
        subscription.trial_end = Time.at(self.trial_ends_at).to_i
      else
        subscription.trial_end = 'now'
      end

      subscription = subscription.save

      # Finally, we will remove the ending timestamp from the user's record in the
      # local database to indicate that the subscription is active again and is
      # no longer "cancelled". Then we will save this record in the database.
      self.update({
        :stripe_status => subscription.status,
        :ends_at => nil,
      })

      self
    end

    # Determine if the subscription has pending updates.
    def pending
      ! self.as_stripe_subscription.pending_update.nil?
    end

    # Invoice the subscription outside of the regular billing cycle.
    def invoice(options = {})
      begin
        self.user.invoice(options.merge({
          :subscription => self.stripe_id
        }))
      rescue IncompletePaymentError => e
        # Set the new Stripe subscription status immediately when payment fails...
        self.update(stripe_status: e.payment.invoice.subscription.status)

        raise e
      end
    end

    # Get the latest invoice for the subscription.
    def latest_invoice
      stripe_subscription = self.as_stripe_subscription(['latest_invoice'])

      Invoice.new(self.user, stripe_subscription.latest_invoice)
    end

    # Sync the tax percentage of the user to the subscription.
    def sync_tax_percentage
      subscription = self.as_stripe_subscription

      subscription.tax_percentage = self.user.tax_percentage

      subscription.save
    end

    # Sync the tax rates of the user to the subscription.
    def sync_tax_rates
      subscription = self.as_stripe_subscription

      subscription.default_tax_rates = self.user.tax_rates

      subscription.save

      self.items.each do |item|
        stripe_subscription_item = item.as_stripe_subscription_item

        stripe_subscription_item.tax_rates = self.get_plan_tax_rates_for_payload(item.stripe_plan)

        stripe_subscription_item.save
      end
    end

    # Get the plan tax rates for the Stripe payload.
    def get_plan_tax_rates_for_payload(plan)
      tax_rates = self.user.plan_tax_rates

      unless tax_rates.empty?
        tax_rates[plan] || nil
      end
    end

    # Determine if the subscription has an incomplete payment.
    def has_incomplete_payment
      self.past_due || self.incomplete
    end

    # Get the latest payment for a Subscription.
    def latest_payment
      payment_intent = self.as_stripe_subscription(['latest_invoice.payment_intent'])
        .latest_invoice
        .payment_intent

      payment_intent ? Payment.new(payment_intent) : nil
    end

    # Make sure a subscription is not incomplete when performing changes.
    def guard_against_incomplete
      raise Reji::SubscriptionUpdateFailureError.incomplete_subscription(self) if self.incomplete
    end

    # Make sure a plan argument is provided when the subscription is a multi plan subscription.
    def guard_against_multiple_plans
      raise ArgumentError.new('This method requires a plan argument since the subscription has multiple plans.') if self.has_multiple_plans
    end

    # Update the underlying Stripe subscription information for the model.
    def update_stripe_subscription(options = {})
      Stripe::Subscription.update(
        self.stripe_id, options, self.owner.stripe_options
      )
    end

    # Get the subscription as a Stripe subscription object.
    def as_stripe_subscription(expand = {})
      Stripe::Subscription::retrieve(
        {:id => self.stripe_id, :expand => expand}, self.owner.stripe_options
      )
    end

    protected

    # Parse the given plans for a swap operation.
    def parse_swap_plans(plans)
      plans.map {
        |plan| [plan, {
          :plan => plan,
          :tax_rates => self.get_plan_tax_rates_for_payload(plan)
        }]
      }.to_h
    end

    # Merge the items that should be deleted during swap into the given items collection.
    def merge_items_that_should_be_deleted_during_swap(items)
      self.as_stripe_subscription.items.data.each do |stripe_subscription_item|
        plan = stripe_subscription_item.plan.id

        item = items.key?(plan) ? items[plan] : {}

        if item.empty?
          item[:deleted] = true
        end

        items[plan] = item.merge({:id => stripe_subscription_item.id})
      end

      items
    end

    # Get the options array for a swap operation.
    def get_swap_options(items, options)
      payload = {
        :items => items.values,
        :payment_behavior => self.payment_behavior,
        :proration_behavior => self.prorate_behavior,
        :expand => ['latest_invoice.payment_intent'],
      }

      payload[:cancel_at_period_end] = false if payload[:payment_behavior] != 'pending_if_incomplete'

      payload = payload.merge(options)

      payload[:billing_cycle_anchor] = @billing_cycle_anchor unless @billing_cycle_anchor.nil?

      payload[:trial_end] = self.on_trial ? self.trial_ends_at : 'now'

      payload
    end
  end
end
