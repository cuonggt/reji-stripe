# frozen_string_literal: true

module Reji
  class IncompletePaymentError < StandardError
    attr_accessor :payment

    def initialize(payment, message = '')
      super(message)

      @payment = payment
    end
  end

  class PaymentActionRequiredError < IncompletePaymentError
    def self.incomplete(payment)
      self.new(payment, 'The payment attempt failed because additional action is required before it can be completed.')
    end
  end

  class PaymentFailureError < IncompletePaymentError
    def self.invalid_payment_method(payment)
      self.new(payment, 'The payment attempt failed because of an invalid payment method.')
    end
  end

  class CustomerAlreadyCreatedError < StandardError
    def self.exists(owner)
      self.new("#{owner.class.name} is already a Stripe customer with ID #{owner.stripe_id}.")
    end
  end

  class InvalidCustomerError < StandardError
    def self.not_yet_created(owner)
      self.new("#{owner.class.name} is not a Stripe customer yet. See the create_as_stripe_customer method.")
    end
  end

  class InvalidPaymentMethodError < StandardError
    def self.invalid_owner(payment_method, owner)
      self.new("The payment method `#{payment_method.id}` does not belong to this customer `#{owner.stripe_id}`.")
    end
  end

  class InvalidInvoiceError < StandardError
    def self.invalid_owner(invoice, owner)
      self.new("The invoice `#{invoice.id}` does not belong to this customer `#{owner.stripe_id}`.")
    end
  end

  class SubscriptionUpdateFailureError < StandardError
    def self.incomplete_subscription(subscription)
      self.new("The subscription \"#{subscription.stripe_id}\" cannot be updated because its payment is incomplete.")
    end

    def self.duplicate_plan(subscription, plan)
      self.new("The plan \"#{plan}\" is already attached to subscription \"#{subscription.stripe_id}\".")
    end

    def self.cannot_delete_last_plan(subscription)
      self.new("The plan on subscription \"#{subscription.stripe_id}\" cannot be removed because it is the last one.")
    end
  end
end
