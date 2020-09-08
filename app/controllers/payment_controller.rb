# frozen_string_literal: true

module Reji
  class PaymentController < ActionController::Base
    def show
      # @stripe_key = Reji.configuration.key

      # @payment = Reji::Payment.new(Stripe::PaymentIntent.retrieve(params[:id], Reji.stripe_options))

      # @redirect = params[:redirect]

      render template: 'payment'
    end
  end
end
