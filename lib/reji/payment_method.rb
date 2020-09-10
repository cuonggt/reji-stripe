# frozen_string_literal: true

module Reji
  class PaymentMethod
    def initialize(owner, payment_method)
      if owner.stripe_id != payment_method.customer
        raise Reji::InvalidPaymentMethodError.invalid_owner(payment_method, owner)
      end

      @owner = owner
      @payment_method = payment_method
    end

    # Delete the payment method.
    def delete
      @owner.remove_payment_method(@payment_method)
    end

    # Get the Stripe model instance.
    attr_reader :owner

    # Get the Stripe PaymentMethod instance.
    def as_stripe_payment_method
      @payment_method
    end

    # Dynamically get values from the Stripe PaymentMethod.
    def method_missing(key)
      @payment_method[key]
    end

    def respond_to_missing?(method_name, include_private = false)
      super
    end
  end
end
