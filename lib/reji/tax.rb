# frozen_string_literal: true

module Reji
  class Tax
    def initialize(amount, currency, tax_rate)
      @amount = amount
      @currency = currency
      @tax_rate = tax_rate
    end

    # Get the applied currency.
    attr_reader :currency

    # Get the total tax that was paid (or will be paid).
    def amount
      format_amount(@amount)
    end

    # Get the raw total tax that was paid (or will be paid).
    def raw_amount
      @amount
    end

    # Determine if the tax is inclusive or not.
    def inclusive?
      @tax_rate.inclusive
    end

    # Stripe::TaxRate
    attr_reader :tax_rate

    # Dynamically get values from the Stripe TaxRate.
    def method_missing(key)
      @tax_rate[key]
    end

    def respond_to_missing?(method_name, include_private = false)
      super
    end

    # Format the given amount into a displayable currency.
    protected def format_amount(amount)
      Reji.format_amount(amount, @currency)
    end
  end
end
