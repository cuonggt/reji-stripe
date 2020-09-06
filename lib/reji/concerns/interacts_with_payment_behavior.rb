# frozen_string_literal: true

module Reji
  module InteractsWithPaymentBehavior
    extend ActiveSupport::Concern

    # Allow subscription changes even if payment fails.
    def allow_payment_failures
      @payment_behavior = 'allow_incomplete'

      self
    end

    # Set any subscription change as pending until payment is successful.
    def pending_if_payment_fails
      @payment_behavior = 'pending_if_incomplete'

      self
    end

    # Prevent any subscription change if payment is unsuccessful.
    def error_if_payment_fails
      @payment_behavior = 'error_if_incomplete'

      self
    end

    # Determine the payment behavior when updating the subscription.
    def payment_behavior
      @payment_behavior ||= 'allow_incomplete'
    end
  end
end
