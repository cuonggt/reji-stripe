# frozen_string_literal: true

module Reji
  class Subscription < ActiveRecord::Base
    include Reji::InteractsWithPaymentBehavior
    include Reji::Prorates

    has_many :items, class_name: 'SubscriptionItem'
    belongs_to :owner, class_name: Reji.configuration.model, foreign_key: Reji.configuration.model_id

    scope :incomplete, -> { where(stripe_status: 'incomplete') }
    scope :past_due, -> { where(stripe_status: 'past_due') }
    scope :active, lambda {
      query = where(ends_at: nil).or(on_grace_period)
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
    scope :on_trial, -> { where.not(trial_ends_at: nil).where('trial_ends_at > ?', Time.current) }
    scope :not_on_trial, -> { where(trial_ends_at: nil).or(where('trial_ends_at <= ?', Time.current)) }
    scope :on_grace_period, -> { where.not(ends_at: nil).where('ends_at > ?', Time.current) }
    scope :not_on_grace_period, -> { where(ends_at: nil).or(where('ends_at <= ?', Time.current)) }

    # The date on which the billing cycle should be anchored.
    @billing_cycle_anchor = nil

    # Get the user that owns the subscription.
    def user
      owner
    end

    # Determine if the subscription has multiple plans.
    def multiple_plans?
      stripe_plan.nil?
    end

    # Determine if the subscription has a single plan.
    def single_plan?
      !multiple_plans?
    end

    # Determine if the subscription has a specific plan.
    def plan?(plan)
      return items.any? { |item| item.stripe_plan == plan } if multiple_plans?

      stripe_plan == plan
    end

    # Get the subscription item for the given plan.
    def find_item_or_fail(plan)
      items.where(stripe_plan: plan).first
    end

    # Determine if the subscription is active, on trial, or within its grace period.
    def valid
      active || on_trial || on_grace_period
    end

    # Determine if the subscription is incomplete.
    def incomplete
      stripe_status == 'incomplete'
    end

    # Determine if the subscription is past due.
    def past_due
      stripe_status == 'past_due'
    end

    # Determine if the subscription is active.
    def active
      (ends_at.nil? || on_grace_period) &&
        stripe_status != 'incomplete' &&
        stripe_status != 'incomplete_expired' &&
        stripe_status != 'unpaid' &&
        (!Reji.deactivate_past_due || stripe_status != 'past_due')
    end

    # Sync the Stripe status of the subscription.
    def sync_stripe_status
      subscription = as_stripe_subscription

      update({ stripe_status: subscription.status })
    end

    # Determine if the subscription is recurring and not on trial.
    def recurring
      !on_trial && !cancelled
    end

    # Determine if the subscription is no longer active.
    def cancelled
      !ends_at.nil?
    end

    # Determine if the subscription has ended and the grace period has expired.
    def ended
      !!(cancelled && !on_grace_period)
    end

    # Determine if the subscription is within its trial period.
    def on_trial
      !!(trial_ends_at && trial_ends_at.future?)
    end

    # Determine if the subscription is within its grace period after cancellation.
    def on_grace_period
      !!(ends_at && ends_at.future?)
    end

    # Increment the quantity of the subscription.
    def increment_quantity(count = 1, plan = nil)
      guard_against_incomplete

      if plan
        find_item_or_fail(plan)
          .set_proration_behavior(proration_behavior)
          .increment_quantity(count)

        return self
      end

      guard_against_multiple_plans

      update_quantity(quantity + count, plan)
    end

    # Increment the quantity of the subscription, and invoice immediately.
    def increment_and_invoice(count = 1, plan = nil)
      guard_against_incomplete

      always_invoice

      if plan
        find_item_or_fail(plan)
          .set_proration_behavior(proration_behavior)
          .increment_quantity(count)

        return self
      end

      guard_against_multiple_plans

      increment_quantity(count, plan)
    end

    # Decrement the quantity of the subscription.
    def decrement_quantity(count = 1, plan = nil)
      guard_against_incomplete

      if plan
        find_item_or_fail(plan)
          .set_proration_behavior(proration_behavior)
          .decrement_quantity(count)

        return self
      end

      guard_against_multiple_plans

      update_quantity([1, quantity - count].max, plan)
    end

    # Update the quantity of the subscription.
    def update_quantity(quantity, plan = nil)
      guard_against_incomplete

      if plan
        find_item_or_fail(plan)
          .set_proration_behavior(proration_behavior)
          .update_quantity(quantity)

        return self
      end

      guard_against_multiple_plans

      stripe_subscription = as_stripe_subscription
      stripe_subscription.quantity = quantity
      stripe_subscription.payment_behavior = payment_behavior
      stripe_subscription.proration_behavior = proration_behavior
      stripe_subscription.save

      update(quantity: quantity)

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
      raise ArgumentError, "Extending a subscription's trial requires a date in the future." unless date.future?

      subscription = as_stripe_subscription
      subscription.trial_end = date.to_i
      subscription.save

      update(trial_ends_at: date)

      self
    end

    # Swap the subscription to new Stripe plans.
    def swap(plans, options = {})
      plans = [plans] unless plans.instance_of? Array

      raise ArgumentError, 'Please provide at least one plan when swapping.' if plans.empty?

      guard_against_incomplete

      items = merge_items_that_should_be_deleted_during_swap(parse_swap_plans(plans))

      stripe_subscription = Stripe::Subscription.update(
        stripe_id,
        get_swap_options(items, options),
        owner.stripe_options
      )

      update({
        stripe_status: stripe_subscription.status,
        stripe_plan: stripe_subscription.plan ? stripe_subscription.plan.id : nil,
        quantity: stripe_subscription.quantity,
        ends_at: nil,
      })

      stripe_subscription.items.each do |item|
        self.items.find_or_create_by(stripe_id: item.id) do |subscription_item|
          subscription_item.stripe_plan = item.plan.id
          subscription_item.quantity = item.quantity
        end
      end

      # Delete items that aren't attached to the subscription anymore...
      self.items.where('stripe_plan NOT IN (?)', items.values.pluck(:plan).compact).destroy_all

      Payment.new(stripe_subscription.latest_invoice.payment_intent).validate if incomplete_payment?

      self
    end

    # Swap the subscription to new Stripe plans, and invoice immediately.
    def swap_and_invoice(plans, options = {})
      always_invoice

      swap(plans, options)
    end

    # Add a new Stripe plan to the subscription.
    def add_plan(plan, quantity = 1, options = {})
      guard_against_incomplete

      if items.any? { |item| item.stripe_plan == plan }
        raise Reji::SubscriptionUpdateFailureError.duplicate_plan(self, plan)
      end

      subscription = as_stripe_subscription

      item = subscription.items.create({
        plan: plan,
        quantity: quantity,
        tax_rates: get_plan_tax_rates_for_payload(plan),
        payment_behavior: payment_behavior,
        proration_behavior: proration_behavior,
      }.merge(options))

      items.create({
        stripe_id: item.id,
        stripe_plan: plan,
        quantity: quantity,
      })

      if single_plan?
        update({
          stripe_plan: nil,
          quantity: nil,
        })
      end

      self
    end

    # Add a new Stripe plan to the subscription, and invoice immediately.
    def add_plan_and_invoice(plan, quantity = 1, options = {})
      always_invoice

      add_plan(plan, quantity, options)
    end

    # Remove a Stripe plan from the subscription.
    def remove_plan(plan)
      raise Reji::SubscriptionUpdateFailureError.cannot_delete_last_plan(self) if single_plan?

      item = find_item_or_fail(plan)

      item.as_stripe_subscription_item.delete({
        proration_behavior: proration_behavior,
      })

      items.where(stripe_plan: plan).destroy_all

      if items.count < 2
        item = items.first

        update({
          stripe_plan: item.stripe_plan,
          quantity: quantity,
        })
      end

      self
    end

    # Cancel the subscription at the end of the billing period.
    def cancel
      subscription = as_stripe_subscription

      subscription.cancel_at_period_end = true

      subscription = subscription.save

      self.stripe_status = subscription.status

      # If the user was on trial, we will set the grace period to end when the trial
      # would have ended. Otherwise, we'll retrieve the end of the billing period
      # period and make that the end of the grace period for this current user.
      self.ends_at = on_trial ? trial_ends_at : Time.zone.at(subscription.current_period_end)

      save

      self
    end

    # Cancel the subscription immediately.
    def cancel_now
      as_stripe_subscription.cancel({
        prorate: proration_behavior == 'create_prorations',
      })

      mark_as_cancelled

      self
    end

    # Cancel the subscription and invoice immediately.
    def cancel_now_and_invoice
      as_stripe_subscription.cancel({
        invoice_now: true,
        prorate: proration_behavior == 'create_prorations',
      })

      mark_as_cancelled

      self
    end

    # Mark the subscription as cancelled.
    def mark_as_cancelled
      update({
        stripe_status: 'canceled',
        ends_at: Time.current,
      })
    end

    # Resume the cancelled subscription.
    def resume
      raise ArgumentError, 'Unable to resume subscription that is not within grace period.' unless on_grace_period

      subscription = as_stripe_subscription

      subscription.cancel_at_period_end = false

      subscription.trial_end = on_trial ? Time.zone.at(trial_ends_at).to_i : 'now'

      subscription = subscription.save

      # Finally, we will remove the ending timestamp from the user's record in the
      # local database to indicate that the subscription is active again and is
      # no longer "cancelled". Then we will save this record in the database.
      update({
        stripe_status: subscription.status,
        ends_at: nil,
      })

      self
    end

    # Determine if the subscription has pending updates.
    def pending
      !as_stripe_subscription.pending_update.nil?
    end

    # Invoice the subscription outside of the regular billing cycle.
    def invoice(options = {})
      user.invoice(options.merge({
        subscription: stripe_id,
      }))
    rescue IncompletePaymentError => e
      # Set the new Stripe subscription status immediately when payment fails...
      update(stripe_status: e.payment.invoice.subscription.status)

      raise e
    end

    # Get the latest invoice for the subscription.
    def latest_invoice
      stripe_subscription = as_stripe_subscription(['latest_invoice'])

      Invoice.new(user, stripe_subscription.latest_invoice)
    end

    # Sync the tax percentage of the user to the subscription.
    def sync_tax_percentage
      subscription = as_stripe_subscription

      subscription.tax_percentage = user.tax_percentage

      subscription.save
    end

    # Sync the tax rates of the user to the subscription.
    def sync_tax_rates
      subscription = as_stripe_subscription

      subscription.default_tax_rates = user.tax_rates

      subscription.save

      items.each do |item|
        stripe_subscription_item = item.as_stripe_subscription_item

        stripe_subscription_item.tax_rates = get_plan_tax_rates_for_payload(item.stripe_plan)

        stripe_subscription_item.save
      end
    end

    # Get the plan tax rates for the Stripe payload.
    def get_plan_tax_rates_for_payload(plan)
      tax_rates = user.plan_tax_rates

      tax_rates[plan] || nil unless tax_rates.empty?
    end

    # Determine if the subscription has an incomplete payment.
    def incomplete_payment?
      past_due || incomplete
    end

    # Get the latest payment for a Subscription.
    def latest_payment
      payment_intent = as_stripe_subscription(['latest_invoice.payment_intent'])
        .latest_invoice
        .payment_intent

      payment_intent ? Payment.new(payment_intent) : nil
    end

    # Make sure a subscription is not incomplete when performing changes.
    def guard_against_incomplete
      raise Reji::SubscriptionUpdateFailureError.incomplete_subscription(self) if incomplete
    end

    # Make sure a plan argument is provided when the subscription is a multi plan subscription.
    def guard_against_multiple_plans
      return unless multiple_plans?

      raise ArgumentError, 'This method requires a plan argument since the subscription has multiple plans.'
    end

    # Update the underlying Stripe subscription information for the model.
    def update_stripe_subscription(options = {})
      Stripe::Subscription.update(
        stripe_id, options, owner.stripe_options
      )
    end

    # Get the subscription as a Stripe subscription object.
    def as_stripe_subscription(expand = {})
      Stripe::Subscription.retrieve(
        { id: stripe_id, expand: expand }, owner.stripe_options
      )
    end

    # Parse the given plans for a swap operation.
    protected def parse_swap_plans(plans)
      plans.map do |plan|
        [plan, {
          plan: plan,
          tax_rates: get_plan_tax_rates_for_payload(plan),
        },]
      end.to_h
    end

    # Merge the items that should be deleted during swap into the given items collection.
    protected def merge_items_that_should_be_deleted_during_swap(items)
      as_stripe_subscription.items.data.each do |stripe_subscription_item|
        plan = stripe_subscription_item.plan.id

        item = items.key?(plan) ? items[plan] : {}

        item[:deleted] = true if item.empty?

        items[plan] = item.merge({ id: stripe_subscription_item.id })
      end

      items
    end

    # Get the options array for a swap operation.
    protected def get_swap_options(items, options)
      payload = {
        items: items.values,
        payment_behavior: payment_behavior,
        proration_behavior: proration_behavior,
        expand: ['latest_invoice.payment_intent'],
      }

      payload[:cancel_at_period_end] = false if payload[:payment_behavior] != 'pending_if_incomplete'

      payload = payload.merge(options)

      payload[:billing_cycle_anchor] = @billing_cycle_anchor unless @billing_cycle_anchor.nil?

      payload[:trial_end] = on_trial ? trial_ends_at : 'now'

      payload
    end
  end
end
