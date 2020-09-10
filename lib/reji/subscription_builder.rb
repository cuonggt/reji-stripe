# frozen_string_literal: true

module Reji
  class SubscriptionBuilder
    include Reji::InteractsWithPaymentBehavior
    include Reji::Prorates

    # Create a new subscription builder instance.
    def initialize(owner, name, plans = [])
      @owner = owner
      @name = name
      @trial_expires = nil # The date and time the trial will expire.
      @skip_trial = false # Indicates that the trial should end immediately.
      @billing_cycle_anchor = nil # The date on which the billing cycle should be anchored.
      @coupon = nil # The coupon code being applied to the customer.
      @metadata = nil # The metadata to apply to the subscription.
      @items = {}

      plans = [plans] unless plans.instance_of? Array

      plans.each { |plan| self.plan(plan) }
    end

    # Set a plan on the subscription builder.
    def plan(plan, quantity = 1)
      options = {
        plan: plan,
        quantity: quantity,
      }

      tax_rates = get_plan_tax_rates_for_payload(plan)

      options[:tax_rates] = tax_rates if tax_rates

      @items[plan] = options

      self
    end

    # Specify the quantity of a subscription item.
    def quantity(quantity, plan = nil)
      if plan.nil?
        raise ArgumentError, 'Plan is required when creating multi-plan subscriptions.' if @items.length > 1

        plan = @items.values[0][:plan]
      end

      self.plan(plan, quantity)
    end

    # Specify the number of days of the trial.
    def trial_days(trial_days)
      @trial_expires = Time.current + trial_days.days

      self
    end

    # Specify the ending date of the trial.
    def trial_until(trial_until)
      @trial_expires = trial_until

      self
    end

    # Force the trial to end immediately.
    def skip_trial
      @skip_trial = true

      self
    end

    # Change the billing cycle anchor on a plan creation.
    def anchor_billing_cycle_on(date)
      @billing_cycle_anchor = date

      self
    end

    # The coupon to apply to a new subscription.
    def with_coupon(coupon)
      @coupon = coupon

      self
    end

    # The metadata to apply to a new subscription.
    def with_metadata(metadata)
      @metadata = metadata

      self
    end

    # Add a new Stripe subscription to the Stripe model.
    def add(customer_options = {}, subscription_options = {})
      create(nil, customer_options, subscription_options)
    end

    # Create a new Stripe subscription.
    def create(payment_method = nil, customer_options = {}, subscription_options = {})
      customer = get_stripe_customer(payment_method, customer_options)

      payload = { customer: customer.id }.merge(build_payload).merge(subscription_options)

      stripe_subscription = Stripe::Subscription.create(
        payload,
        @owner.stripe_options
      )

      subscription = @owner.subscriptions.create({
        name: @name,
        stripe_id: stripe_subscription.id,
        stripe_status: stripe_subscription.status,
        stripe_plan: stripe_subscription.plan ? stripe_subscription.plan.id : nil,
        quantity: stripe_subscription.quantity,
        trial_ends_at: @skip_trial ? nil : @trial_expires,
        ends_at: nil,
      })

      stripe_subscription.items.each do |item|
        subscription.items.create({
          stripe_id: item.id,
          stripe_plan: item.plan.id,
          quantity: item.quantity,
        })
      end

      Payment.new(stripe_subscription.latest_invoice.payment_intent).validate if subscription.incomplete_payment?

      subscription
    end

    # Get the Stripe customer instance for the current user and payment method.
    protected def get_stripe_customer(payment_method = nil, options = {})
      customer = @owner.create_or_get_stripe_customer(options)

      @owner.update_default_payment_method(payment_method) if payment_method

      customer
    end

    # Build the payload for subscription creation.
    protected def build_payload
      payload = {
        billing_cycle_anchor: @billing_cycle_anchor,
        coupon: @coupon,
        expand: ['latest_invoice.payment_intent'],
        metadata: @metadata,
        items: @items.values,
        payment_behavior: payment_behavior,
        proration_behavior: proration_behavior,
        trial_end: get_trial_end_for_payload,
        off_session: true,
      }

      tax_rates = get_tax_rates_for_payload

      if tax_rates
        payload[:default_tax_rates] = tax_rates

        return payload
      end

      tax_percentage = get_tax_percentage_for_payload

      payload[:tax_percent] = tax_percentage if tax_percentage

      payload
    end

    # Get the trial ending date for the Stripe payload.
    protected def get_trial_end_for_payload
      return 'now' if @skip_trial

      @trial_expires&.to_i
    end

    # Get the tax percentage for the Stripe payload.
    protected def get_tax_percentage_for_payload
      tax_percentage = @owner.tax_percentage

      tax_percentage if tax_percentage > 0
    end

    # Get the tax rates for the Stripe payload.
    protected def get_tax_rates_for_payload
      tax_rates = @owner.tax_rates

      tax_rates unless tax_rates.empty?
    end

    # Get the plan tax rates for the Stripe payload.
    protected def get_plan_tax_rates_for_payload(plan)
      tax_rates = @owner.plan_tax_rates

      tax_rates[plan] || nil unless tax_rates.empty?
    end
  end
end
