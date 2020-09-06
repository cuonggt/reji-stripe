# frozen_string_literal: true

module Reji
  class SubscriptionItem < ActiveRecord::Base
    include Reji::InteractsWithPaymentBehavior
    include Reji::Prorates

    belongs_to :subscription

    # Increment the quantity of the subscription item.
    def increment_quantity(count = 1)
      self.update_quantity(self.quantity + count)

      self
    end

    # Increment the quantity of the subscription item, and invoice immediately.
    def increment_and_invoice(count = 1)
      self.always_invoice

      self.increment_quantity(count)

      self
    end

    # Decrement the quantity of the subscription item.
    def decrement_quantity(count = 1)
      self.update_quantity([1, self.quantity - count].max)

      self
    end

    # Update the quantity of the subscription item.
    def update_quantity(quantity)
      self.subscription.guard_against_incomplete

      stripe_subscription_item = self.as_stripe_subscription_item
      stripe_subscription_item.quantity = quantity
      stripe_subscription_item.payment_behavior = self.payment_behavior
      stripe_subscription_item.proration_behavior = self.prorate_behavior
      stripe_subscription_item.save

      self.update(quantity: quantity)

      self.subscription.update(quantity: quantity) if self.subscription.has_single_plan

      self
    end

    # Swap the subscription item to a new Stripe plan.
    def swap(plan, options = {})
      self.subscription.guard_against_incomplete

      options = {
        :plan => plan,
        :quantity => self.quantity,
        :payment_behavior => self.payment_behavior,
        :proration_behavior => self.prorate_behavior,
        :tax_rates => self.subscription.get_plan_tax_rates_for_payload(plan)
      }.merge(options)

      item = Stripe::SubscriptionItem::update(
        self.stripe_id,
        options,
        self.subscription.owner.stripe_options
      )

      self.update(stripe_plan: plan, quantity: item.quantity)

      self.subscription.update(stripe_plan: plan, quantity: item.quantity) if self.subscription.has_single_plan

      self
    end

    # Swap the subscription item to a new Stripe plan, and invoice immediately.
    def swap_and_invoice(plan, options = {})
      self.always_invoice

      self.swap(plan, options)
    end

    # Update the underlying Stripe subscription item information for the model.
    def update_stripe_subscription_item(options = {})
      Stripe::SubscriptionItem.update(
        self.stripe_id, options, self.subscription.owner.stripe_options
      )
    end

    # Get the subscription as a Stripe subscription item object.
    def as_stripe_subscription_item(expand = {})
      Stripe::SubscriptionItem.retrieve(
        {:id => self.stripe_id, :expand => expand},
        self.subscription.owner.stripe_options
      )
    end
  end
end
