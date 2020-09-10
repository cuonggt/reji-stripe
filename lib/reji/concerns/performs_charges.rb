# frozen_string_literal: true

module Reji
  module PerformsCharges
    extend ActiveSupport::Concern

    # Make a "one off" charge on the customer for the given amount.
    def charge(amount, payment_method, options = {})
      options = {
        confirmation_method: 'automatic',
        confirm: true,
        currency: preferred_currency,
      }.merge(options)

      options[:amount] = amount
      options[:payment_method] = payment_method
      options[:customer] = stripe_id if stripe_id?

      payment = Payment.new(
        Stripe::PaymentIntent.create(options, stripe_options)
      )

      payment.validate

      payment
    end

    # Refund a customer for a charge.
    def refund(payment_intent, options = {})
      Stripe::Refund.create(
        { payment_intent: payment_intent }.merge(options),
        stripe_options
      )
    end
  end
end
