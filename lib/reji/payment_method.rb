# frozen_string_literal: true

module Reji
  class PaymentMethod
    def initialize(owner, payment_method)
      raise Reji::InvalidPaymentMethodError.invalid_owner(payment_method, owner) if owner.stripe_id != payment_method.customer

      @owner = owner
      @payment_method = payment_method
    end

    # Delete the payment method.
    def delete
      @owner.remove_payment_method(@payment_method)
    end

    # Get the Stripe model instance.
    def owner
      @owner
    end

    # Get the Stripe PaymentMethod instance.
    def as_stripe_payment_method
      @payment_method
    end

    # Dynamically get values from the Stripe PaymentMethod.
    def method_missing(key)
      @payment_method[key]
    end
  end
end
