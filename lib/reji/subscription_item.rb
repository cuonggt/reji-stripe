# frozen_string_literal: true

module Reji
  class SubscriptionItem < ActiveRecord::Base
    include Reji::InteractsWithPaymentBehavior
    include Reji::Prorates

    belongs_to :subscription

    # Increment the quantity of the subscription item.
    def increment_quantity(count = 1)
      update_quantity(quantity + count)

      self
    end

    # Increment the quantity of the subscription item, and invoice immediately.
    def increment_and_invoice(count = 1)
      always_invoice

      increment_quantity(count)

      self
    end

    # Decrement the quantity of the subscription item.
    def decrement_quantity(count = 1)
      update_quantity([1, quantity - count].max)

      self
    end

    # Update the quantity of the subscription item.
    def update_quantity(quantity)
      subscription.guard_against_incomplete

      stripe_subscription_item = as_stripe_subscription_item
      stripe_subscription_item.quantity = quantity
      stripe_subscription_item.payment_behavior = payment_behavior
      stripe_subscription_item.proration_behavior = proration_behavior
      stripe_subscription_item.save

      update(quantity: quantity)

      subscription.update(quantity: quantity) if subscription.single_plan?

      self
    end

    # Swap the subscription item to a new Stripe plan.
    def swap(plan, options = {})
      subscription.guard_against_incomplete

      options = {
        plan: plan,
        quantity: quantity,
        payment_behavior: payment_behavior,
        proration_behavior: proration_behavior,
        tax_rates: subscription.get_plan_tax_rates_for_payload(plan),
      }.merge(options)

      item = Stripe::SubscriptionItem.update(
        stripe_id,
        options,
        subscription.owner.stripe_options
      )

      update(stripe_plan: plan, quantity: item.quantity)

      subscription.update(stripe_plan: plan, quantity: item.quantity) if subscription.single_plan?

      self
    end

    # Swap the subscription item to a new Stripe plan, and invoice immediately.
    def swap_and_invoice(plan, options = {})
      always_invoice

      swap(plan, options)
    end

    # Update the underlying Stripe subscription item information for the model.
    def update_stripe_subscription_item(options = {})
      Stripe::SubscriptionItem.update(
        stripe_id, options, subscription.owner.stripe_options
      )
    end

    # Get the subscription as a Stripe subscription item object.
    def as_stripe_subscription_item(expand = {})
      Stripe::SubscriptionItem.retrieve(
        { id: stripe_id, expand: expand },
        subscription.owner.stripe_options
      )
    end
  end
end
