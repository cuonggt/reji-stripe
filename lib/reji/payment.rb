# frozen_string_literal: true

module Reji
  class Payment
    def initialize(payment_intent)
      @payment_intent = payment_intent
    end

    # Get the total amount that will be paid.
    def amount
      Reji.format_amount(raw_amount, @payment_intent.currency)
    end

    # Get the raw total amount that will be paid.
    def raw_amount
      @payment_intent.amount
    end

    # The Stripe PaymentIntent client secret.
    def client_secret
      @payment_intent.client_secret
    end

    # Determine if the payment needs a valid payment method.
    def requires_payment_method
      @payment_intent.status == 'requires_payment_method'
    end

    # Determine if the payment needs an extra action like 3D Secure.
    def requires_action
      @payment_intent.status == 'requires_action'
    end

    # Determine if the payment was cancelled.
    def cancelled?
      @payment_intent.status == 'canceled'
    end

    # Determine if the payment was successful.
    def succeeded?
      @payment_intent.status == 'succeeded'
    end

    # Validate if the payment intent was successful and throw an exception if not.
    def validate
      raise Reji::PaymentFailureError.invalid_payment_method(self) if requires_payment_method

      raise Reji::PaymentActionRequiredError.incomplete(self) if requires_action
    end

    # The Stripe PaymentIntent instance.
    def as_stripe_payment_intent
      @payment_intent
    end

    # Dynamically get values from the Stripe PaymentIntent.
    def method_missing(key)
      @payment_intent[key]
    end

    def respond_to_missing?(method_name, include_private = false)
      super
    end
  end
end
