# frozen_string_literal: true

module Reji
  module ManagesSubscriptions
    extend ActiveSupport::Concern

    included do
      has_many :subscriptions, -> { order(created_at: :desc) }, class_name: 'Reji::Subscription'
    end

    # Begin creating a new subscription.
    def new_subscription(name, plans)
      SubscriptionBuilder.new(self, name, plans)
    end

    # Determine if the Stripe model is on trial.
    def on_trial(name = 'default', plan = nil)
      return true if name == 'default' && plan.nil? && self.on_generic_trial

      subscription = self.subscription(name)

      return false unless subscription && subscription.on_trial

      plan ? subscription.has_plan(plan) : true
    end

    # Determine if the Stripe model is on a "generic" trial at the model level.
    def on_generic_trial
      !! self.trial_ends_at && self.trial_ends_at.future?
    end

    # Determine if the Stripe model has a given subscription.
    def subscribed(name = 'default', plan = nil)
      subscription = self.subscription(name)

      return false unless subscription && subscription.valid?

      plan ? subscription.has_plan(plan) : true
    end

    # Get a subscription instance by name.
    def subscription(name = 'default')
      self.subscriptions
        .sort_by { |subscription| subscription.created_at.to_i }
        .reverse
        .find { |subscription| subscription.name == name }
    end

    # Determine if the customer's subscription has an incomplete payment.
    def has_incomplete_payment(name = 'default')
      subscription = self.subscription(name)

      subscription ? subscription.has_incomplete_payment : false
    end

    # Determine if the Stripe model is actively subscribed to one of the given plans.
    def subscribed_to_plan(plans, name = 'default')
      subscription = self.subscription(name)

      return false unless subscription && subscription.valid?

      plans = [plans] unless plans.instance_of? Array

      plans.each do |plan|
        return true if subscription.has_plan(plan)
      end

      false
    end

    # Determine if the entity has a valid subscription on the given plan.
    def on_plan(plan)
      self.subscriptions.any? { |subscription| subscription.valid && subscription.has_plan(plan) }
    end

    # Get the tax percentage to apply to the subscription.
    def tax_percentage
      0
    end

    # Get the tax rates to apply to the subscription.
    def tax_rates
      []
    end

    # Get the tax rates to apply to individual subscription items.
    def plan_tax_rates
      {}
    end
  end
end
