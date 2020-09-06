# frozen_string_literal: true

require 'stripe'
require 'money'

# Version
require 'reji/version'

require 'reji/configuration'

require 'reji/concerns/manages_customer'
require 'reji/concerns/manages_invoices'
require 'reji/concerns/manages_payment_methods'
require 'reji/concerns/manages_subscriptions'
require 'reji/concerns/performs_charges'
require 'reji/concerns/interacts_with_payment_behavior'
require 'reji/concerns/prorates'

require 'reji/billable'
require 'reji/errors'
require 'reji/invoice'
require 'reji/invoice_line_item'
require 'reji/payment'
require 'reji/payment_method'
require 'reji/subscription'
require 'reji/subscription_builder'
require 'reji/subscription_item'
require 'reji/tax'

module Reji
  # The Stripe API version.
  STRIPE_VERSION = '2020-08-27'

  # Indicates if Reji will mark past due subscriptions as inactive.
  @deactivate_past_due = true

  def self.deactivate_past_due
    @deactivate_past_due
  end

  # Get the billable entity instance by Stripe ID.
  def self.find_billable(stripe_id)
    return if stripe_id.nil?

    model = @configuration.model
    model.constantize.where(stripe_id: stripe_id).first
  end

  # Get the default Stripe API options.
  def self.stripe_options(options = {})
    {
      :api_key => Reji.configuration.secret,
      :stripe_version => Reji::STRIPE_VERSION,
    }.merge(options)
  end

  # Format the given amount into a displayable currency.
  def self.format_amount(amount, currency = nil)
    currency = 'usd' if currency.nil?

    Money.rounding_mode = BigDecimal::ROUND_HALF_EVEN
    Money.locale_backend = :i18n

    money = Money.new(amount, Money::Currency.new(currency.upcase))

    money.format
  end

  # Configure to maintain past due subscriptions as active.
  def self.keep_past_due_subscriptions_active
    @deactivate_past_due = false

    self
  end

  def self.deactivate_past_due=(value)
    @deactivate_past_due = value
  end
end

Stripe.set_app_info('Rails Reji')
