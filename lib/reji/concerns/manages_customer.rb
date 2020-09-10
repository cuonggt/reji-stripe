# frozen_string_literal: true

module Reji
  module ManagesCustomer
    extend ActiveSupport::Concern

    # Determine if the entity has a Stripe customer ID.
    def stripe_id?
      !stripe_id.nil?
    end

    # Create a Stripe customer for the given model.
    def create_as_stripe_customer(options = {})
      raise Reji::CustomerAlreadyCreatedError.exists(self) if stripe_id?

      options[:email] = stripe_email if !options.key?('email') && stripe_email

      # Here we will create the customer instance on Stripe and store the ID of the
      # user from Stripe. This ID will correspond with the Stripe user instances
      # and allow us to retrieve users from Stripe later when we need to work.
      customer = Stripe::Customer.create(
        options, stripe_options
      )

      update({ stripe_id: customer.id })

      customer
    end

    # Update the underlying Stripe customer information for the model.
    def update_stripe_customer(options = {})
      Stripe::Customer.update(
        stripe_id, options, stripe_options
      )
    end

    # Get the Stripe customer instance for the current user or create one.
    def create_or_get_stripe_customer(options = {})
      return as_stripe_customer if stripe_id?

      create_as_stripe_customer(options)
    end

    # Get the Stripe customer for the model.
    def as_stripe_customer
      assert_customer_exists

      Stripe::Customer.retrieve(stripe_id, stripe_options)
    end

    # Get the email address used to create the customer in Stripe.
    def stripe_email
      email
    end

    # Apply a coupon to the billable entity.
    def apply_coupon(coupon)
      assert_customer_exists

      customer = as_stripe_customer

      customer.coupon = coupon

      customer.save
    end

    # Get the Stripe supported currency used by the entity.
    def preferred_currency
      Reji.configuration.currency
    end

    # Get the Stripe billing portal for this customer.
    def billing_portal_url(return_url = nil)
      assert_customer_exists

      session = Stripe::BillingPortal::Session.create({
        customer: stripe_id,
        return_url: return_url || '/',
      }, stripe_options)

      session.url
    end

    # Determine if the customer is not exempted from taxes.
    def not_tax_exempt?
      as_stripe_customer.tax_exempt == 'none'
    end

    # Determine if the customer is exempted from taxes.
    def tax_exempt?
      as_stripe_customer.tax_exempt == 'exempt'
    end

    # Determine if reverse charge applies to the customer.
    def reverse_charge_applies
      as_stripe_customer.tax_exempt == 'reverse'
    end

    # Get the default Stripe API options for the current Billable model.
    def stripe_options(options = {})
      Reji.stripe_options(options)
    end

    # Determine if the entity has a Stripe customer ID and throw an exception if not.
    protected def assert_customer_exists
      raise Reji::InvalidCustomerError.not_yet_created(self) unless stripe_id?
    end
  end
end
