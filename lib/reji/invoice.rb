# frozen_string_literal: true

require 'wicked_pdf'

module Reji
  class Invoice
    def initialize(owner, invoice)
      raise Reji::InvalidInvoiceError.invalid_owner(invoice, owner) if owner.stripe_id != invoice.customer

      @owner = owner
      @invoice = invoice
      @items = nil
      @taxes = nil
    end

    # Get a date for the invoice.
    def date
      Time.zone.at(@invoice.created || @invoice.date)
    end

    # Get the total amount that was paid (or will be paid).
    def total
      Reji.format_amount(raw_total)
    end

    # Get the raw total amount that was paid (or will be paid).
    def raw_total
      @invoice.total + raw_starting_balance
    end

    # Get the total of the invoice (before discounts).
    def subtotal
      Reji.format_amount(@invoice[:subtotal])
    end

    # Determine if the account had a starting balance.
    def starting_balance?
      raw_starting_balance < 0
    end

    # Get the starting balance for the invoice.
    def starting_balance
      Reji.format_amount(raw_starting_balance)
    end

    # Get the raw starting balance for the invoice.
    def raw_starting_balance
      @invoice[:starting_balance] || 0
    end

    # Determine if the invoice has a discount.
    def discount?
      raw_discount > 0
    end

    # Get the discount amount.
    def discount
      format_amount(raw_discount)
    end

    # Get the raw discount amount.
    def raw_discount
      return 0 unless @invoice.discount

      return (@invoice.subtotal * (percent_off / 100)).round.to_i if discount_is_percentage

      raw_amount_off
    end

    # Get the coupon code applied to the invoice.
    def coupon
      return @invoice[:discount][:coupon][:id] if @invoice[:discount]
    end

    # Determine if the discount is a percentage.
    def discount_is_percentage
      return false unless @invoice[:discount]

      !!@invoice[:discount][:coupon][:percent_off]
    end

    # Get the discount percentage for the invoice.
    def percent_off
      coupon ? @invoice[:discount][:coupon][:percent_off] : 0
    end

    # Get the discount amount for the invoice.
    def amount_off
      format_amount(raw_amount_off)
    end

    # Get the raw discount amount for the invoice.
    def raw_amount_off
      amount_off = @invoice[:discount][:coupon][:amount_off]

      amount_off || 0
    end

    # Get the total tax amount.
    def tax
      format_amount(@invoice.tax)
    end

    # Determine if the invoice has tax applied.
    def tax?
      line_items = invoice_items + subscriptions

      line_items.any?(&:tax_rates?)
    end

    # Get the taxes applied to the invoice.
    def taxes
      return @taxes unless @taxes.nil?

      refresh_with_expanded_tax_rates

      @taxes = @invoice.total_tax_amounts
        .sort_by(&:inclusive)
        .reverse
        .map { |tax_amount| Tax.new(tax_amount.amount, @invoice.currency, tax_amount.tax_rate) }

      @taxes
    end

    # Determine if the customer is not exempted from taxes.
    def not_tax_exempt?
      @invoice[:customer_tax_exempt] == 'none'
    end

    # Determine if the customer is exempted from taxes.
    def tax_exempt?
      @invoice[:customer_tax_exempt] == 'exempt'
    end

    # Determine if reverse charge applies to the customer.
    def reverse_charge_applies
      @invoice[:customer_tax_exempt] == 'reverse'
    end

    # Get all of the "invoice item" line items.
    def invoice_items
      invoice_line_items_by_type('invoiceitem')
    end

    # Get all of the "subscription" line items.
    def subscriptions
      invoice_line_items_by_type('subscription')
    end

    # Get all of the invoice items by a given type.
    def invoice_line_items_by_type(type)
      if @items.nil?
        refresh_with_expanded_tax_rates

        @items = @invoice.lines.auto_paging_each
      end

      @items
        .select { |item| item.type == type }
        .map { |item| InvoiceLineItem.new(self, item) }
    end

    # Get the View instance for the invoice.
    def view(data)
      ActionController::Base.new.render_to_string(
        template: 'receipt',
        locals: data.merge({
          invoice: self,
          owner: owner,
          user: owner,
        })
      )
    end

    # Capture the invoice as a PDF and return the raw bytes.
    def pdf(data)
      WickedPdf.new.pdf_from_string(view(data))
    end

    # Create an invoice download response.
    def download(data)
      filename = "#{data[:product]}_#{date.month}_#{date.year}"

      download_as(filename, data)
    end

    # Create an invoice download response with a specific filename.
    def download_as(filename, data)
      { data: pdf(data), filename: filename }
    end

    # Void the Stripe invoice.
    def void(options = {})
      @invoice = @invoice.void_invoice(options, @owner.stripe_options)

      self
    end

    # Get the Stripe model instance.
    attr_reader :owner

    # Get the Stripe invoice instance.
    def as_stripe_invoice
      @invoice
    end

    # Dynamically get values from the Stripe invoice.
    def method_missing(key)
      @invoice[key]
    end

    def respond_to_missing?(method_name, include_private = false)
      super
    end

    # Refresh the invoice with expanded TaxRate objects.
    protected def refresh_with_expanded_tax_rates
      @invoice =
        if @invoice.id
          Stripe::Invoice.retrieve({
            id: @invoice.id,
            expand: [
              'lines.data.tax_amounts.tax_rate',
              'total_tax_amounts.tax_rate',
            ],
          }, @owner.stripe_options)
        else
          # If no invoice ID is present then assume this is the customer's upcoming invoice...
          Stripe::Invoice.upcoming({
            customer: @owner.stripe_id,
            expand: [
              'lines.data.tax_amounts.tax_rate',
              'total_tax_amounts.tax_rate',
            ],
          }, @owner.stripe_options)
        end
    end

    # Format the given amount into a displayable currency.
    protected def format_amount(amount)
      Reji.format_amount(amount, @invoice.currency)
    end
  end
end
