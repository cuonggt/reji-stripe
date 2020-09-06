# frozen_string_literal: true

module Reji
  module ManagesPaymentMethods
    extend ActiveSupport::Concern

    # Create a new SetupIntent instance.
    def create_setup_intent(options = {})
      Stripe::SetupIntent.create(options, self.stripe_options)
    end

    # Determines if the customer currently has a default payment method.
    def has_default_payment_method
      ! self.card_brand.blank?
    end

    # Determines if the customer currently has at least one payment method.
    def has_payment_method
      ! self.payment_methods.empty?
    end

    # Get a collection of the entity's payment methods.
    def payment_methods(parameters = {})
      return [] unless self.has_stripe_id

      parameters = {:limit => 24}.merge(parameters)

      # "type" is temporarily required by Stripe...
      payment_methods = Stripe::PaymentMethod.list(
        {customer: self.stripe_id, type: 'card'}.merge(parameters),
        self.stripe_options
      )

      payment_methods.data.map { |payment_method| PaymentMethod.new(self, payment_method) }
    end

    # Add a payment method to the customer.
    def add_payment_method(payment_method)
      self.assert_customer_exists

      stripe_payment_method = self.resolve_stripe_payment_method(payment_method)

      if stripe_payment_method.customer != self.stripe_id
        stripe_payment_method = stripe_payment_method.attach(
          {:customer => self.stripe_id}, self.stripe_options
        )
      end

      PaymentMethod.new(self, stripe_payment_method)
    end

    # Remove a payment method from the customer.
    def remove_payment_method(payment_method)
      self.assert_customer_exists

      stripe_payment_method = self.resolve_stripe_payment_method(payment_method)

      return if stripe_payment_method.customer != self.stripe_id

      customer = self.as_stripe_customer

      default_payment_method = customer.invoice_settings.default_payment_method

      stripe_payment_method.detach({}, self.stripe_options)

      # If the payment method was the default payment method, we'll remove it manually...
      if stripe_payment_method.id == default_payment_method
        self.update({
          :card_brand => nil,
          :card_last_four => nil,
        })
      end
    end

    # Get the default payment method for the entity.
    def default_payment_method
      return unless self.has_stripe_id

      customer = Stripe::Customer.retrieve({
        :id => self.stripe_id,
        :expand => [
          'invoice_settings.default_payment_method',
          'default_source',
        ]
      }, self.stripe_options)

      if customer.invoice_settings.default_payment_method
        return PaymentMethod.new(
          self,
          customer.invoice_settings.default_payment_method
        )
      end

      # If we can't find a payment method, try to return a legacy source...
      customer.default_source
    end

    # Update customer's default payment method.
    def update_default_payment_method(payment_method)
      self.assert_customer_exists

      customer = self.as_stripe_customer

      stripe_payment_method = self.resolve_stripe_payment_method(payment_method)

      # If the customer already has the payment method as their default, we can bail out
      # of the call now. We don't need to keep adding the same payment method to this
      # model's account every single time we go through this specific process call.
      return if stripe_payment_method.id == customer.invoice_settings.default_payment_method

      payment_method = self.add_payment_method(stripe_payment_method)

      customer.invoice_settings = {:default_payment_method => payment_method.id}

      customer.save

      # Next we will get the default payment method for this user so we can update the
      # payment method details on the record in the database. This will allow us to
      # show that information on the front-end when updating the payment methods.
      self.fill_payment_method_details(payment_method)
      self.save

      payment_method
    end

    # Synchronises the customer's default payment method from Stripe back into the database.
    def update_default_payment_method_from_stripe
      default_payment_method = self.default_payment_method

      if default_payment_method
        if default_payment_method.instance_of? PaymentMethod
          self.fill_payment_method_details(
            default_payment_method.as_stripe_payment_method
          ).save
        else
          self.fill_source_details(default_payment_method).save
        end
      else
        self.update({
          :card_brand => nil,
          :card_last_four => nil,
        })
      end

      self
    end

    # Deletes the entity's payment methods.
    def delete_payment_methods
      self.payment_methods.each { |payment_method| payment_method.delete }

      self.update_default_payment_method_from_stripe
    end

    # Find a PaymentMethod by ID.
    def find_payment_method(payment_method)
      stripe_payment_method = nil

      begin
        stripe_payment_method = self.resolve_stripe_payment_method(payment_method)
      rescue => e
        #
      end

      stripe_payment_method ? PaymentMethod.new(self, stripe_payment_method) : nil
    end

    protected

    # Fills the model's properties with the payment method from Stripe.
    def fill_payment_method_details(payment_method)
      if payment_method.type == 'card'
        self.card_brand = payment_method.card.brand
        self.card_last_four = payment_method.card.last4
      end

      payment_method
    end

    # Fills the model's properties with the source from Stripe.
    def fill_source_details(source)
      if source.instance_of? Stripe::Card
        self.card_brand = source.brand
        self.card_last_four = source.last4
      elsif source.instance_of? Stripe::BankAccount
        self.card_brand = 'Bank Account'
        self.card_last_four = source.last4
      end

      self
    end

    # Resolve a PaymentMethod ID to a Stripe PaymentMethod object.
    def resolve_stripe_payment_method(payment_method)
      return payment_method if payment_method.instance_of? Stripe::PaymentMethod

      Stripe::PaymentMethod.retrieve(
        payment_method, self.stripe_options
      )
    end
  end
end
