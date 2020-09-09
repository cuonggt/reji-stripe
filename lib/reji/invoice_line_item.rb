# frozen_string_literal: true

module Reji
  class InvoiceLineItem
    def initialize(invoice, item)
      @invoice = invoice
      @item = item
    end

    # Get the total for the invoice line item.
    def total
      self.format_amount(@item.amount)
    end

    # Determine if the line item has both inclusive and exclusive tax.
    def has_both_inclusive_and_exclusive_tax
      self.inclusive_tax_percentage > 0 && self.exclusive_tax_percentage > 0
    end

    # Get the total percentage of the default inclusive tax for the invoice line item.
    def inclusive_tax_percentage
      @invoice.is_not_tax_exempt ?
        self.calculate_tax_percentage_by_tax_amount(true) :
        self.calculate_tax_percentage_by_tax_rate(true)
    end

    # Get the total percentage of the default exclusive tax for the invoice line item.
    def exclusive_tax_percentage
      @invoice.is_not_tax_exempt ?
        self.calculate_tax_percentage_by_tax_amount(false) :
        self.calculate_tax_percentage_by_tax_rate(false)
    end

    # Determine if the invoice line item has tax rates.
    def has_tax_rates
      @invoice.is_not_tax_exempt ?
        ! @item.tax_amounts.empty? :
        ! @item.tax_rates.empty?
    end

    # Get a human readable date for the start date.
    def start_date
      self.is_subscription ? Time.at(@item.period.start).strftime('%b %d, %Y') : nil
    end

    # Get a human readable date for the end date.
    def end_date
      self.is_subscription ? Time.at(@item.period.end).strftime('%b %d, %Y') : nil
    end

    # Determine if the invoice line item is for a subscription.
    def is_subscription
      @item.type == 'subscription'
    end

    # Get the Stripe model instance.
    def invoice
      @invoice
    end

    # Get the underlying Stripe invoice line item.
    def as_stripe_invoice_line_item
      @item
    end

    # Dynamically access the Stripe invoice line item instance.
    def method_missing(key)
      @item[key]
    end

    protected

    # Calculate the total tax percentage for either the inclusive or exclusive tax by tax rate.
    def calculate_tax_percentage_by_tax_rate(inclusive)
      return 0 if @item[:tax_rates].empty?

      @item.tax_rates
        .select { |tax_rate| tax_rate[:inclusive] == inclusive }
        .inject(0) { |sum, tax_rate| sum + tax_rate[:percentage] }
        .to_i
    end

    # Calculate the total tax percentage for either the inclusive or exclusive tax by tax amount.
    def calculate_tax_percentage_by_tax_amount(inclusive)
      return 0 if @item[:tax_amounts].blank?

      @item.tax_amounts
        .select { |tax_amount| tax_amount.inclusive == inclusive }
        .inject(0) { |sum, tax_amount| sum + tax_amount[:tax_rate][:percentage] }
        .to_i
    end

    # Format the given amount into a displayable currency.
    def format_amount(amount)
      Reji.format_amount(amount, @item.currency)
    end
  end
end
