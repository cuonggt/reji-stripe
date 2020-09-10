# frozen_string_literal: true

module Reji
  class PaymentController < ActionController::Base
    before_action :verify_redirect_url

    def show
      @stripe_key = Reji.configuration.key

      @payment = Reji::Payment.new(
        Stripe::PaymentIntent.retrieve(
          params[:id], Reji.stripe_options
        )
      )

      @redirect = params[:redirect]

      render template: 'payment'
    end

    private def verify_redirect_url
      return if params[:redirect].blank?

      url = URI(params[:redirect])

      return unless url.host.blank? || url.host != URI(request.original_url).host

      raise ActionController::Forbidden, 'Redirect host mismatch.'
    end
  end
end
