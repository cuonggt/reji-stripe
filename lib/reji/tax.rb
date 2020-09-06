# frozen_string_literal: true

module Reji
  class Tax
    def initialize(amount, currency, tax_rate)
      @amount = amount
      @currency = currency
      @tax_rate = tax_rate
    end

    # Get the applied currency.
    def currency
      @currency
    end

    # Get the total tax that was paid (or will be paid).
    def amount
      self.format_amount(@amount)
    end

    # Get the raw total tax that was paid (or will be paid).
    def raw_amount
      @amount
    end

    # Determine if the tax is inclusive or not.
    def is_inclusive
      @tax_rate.inclusive
    end

    # Stripe::TaxRate
    def tax_rate
      @tax_rate
    end

    # Dynamically get values from the Stripe TaxRate.
    def method_missing(key)
      @tax_rate[key]
    end

    protected

    # Format the given amount into a displayable currency.
    def format_amount(amount)
      Reji.format_amount(amount, @currency)
    end
  end
end
