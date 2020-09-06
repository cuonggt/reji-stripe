# frozen_string_literal: true

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
      Time.at(@invoice.created ? @invoice.created : @invoice.date)
    end

    # Get the total amount that was paid (or will be paid).
    def total
      Reji.format_amount(self.raw_total)
    end

    # Get the raw total amount that was paid (or will be paid).
    def raw_total
      @invoice.total + self.raw_starting_balance
    end

    # Get the total of the invoice (before discounts).
    def subtotal
      Reji.format_amount(@invoice[:subtotal])
    end

    # Determine if the account had a starting balance.
    def has_starting_balance
      self.raw_starting_balance < 0
    end

    # Get the starting balance for the invoice.
    def starting_balance
      Reji.format_amount(self.raw_starting_balance)
    end

    # Get the raw starting balance for the invoice.
    def raw_starting_balance
      @invoice[:starting_balance] ? @invoice[:starting_balance] : 0
    end

    # Determine if the invoice has a discount.
    def has_discount
      self.raw_discount > 0
    end

    # Get the discount amount.
    def discount
      self.format_amount(self.raw_discount)
    end

    # Get the raw discount amount.
    def raw_discount
      return 0 unless @invoice.discount

      return (@invoice.subtotal * (self.percent_off / 100)).round.to_i if self.discount_is_percentage

      self.raw_amount_off
    end

    # Get the coupon code applied to the invoice.
    def coupon
      return @invoice[:discount][:coupon][:id] if @invoice[:discount]
    end

    # Determine if the discount is a percentage.
    def discount_is_percentage
      return false unless @invoice[:discount]

      !! @invoice[:discount][:coupon][:percent_off]
    end

    # Get the discount percentage for the invoice.
    def percent_off
      self.coupon ? @invoice[:discount][:coupon][:percent_off] : 0
    end

    # Get the discount amount for the invoice.
    def amount_off
      self.format_amount(self.raw_amount_off)
    end

    # Get the raw discount amount for the invoice.
    def raw_amount_off
      amount_off = @invoice[:discount][:coupon][:amount_off]

      amount_off ? amount_off : 0
    end

    # Get the total tax amount.
    def tax
      self.format_amount(@invoice.tax)
    end

    # Determine if the invoice has tax applied.
    def has_tax
      line_items = self.invoice_items + self.subscriptions

      line_items.any? { |item| item.has_tax_rates }
    end

    # Get the taxes applied to the invoice.
    def taxes
      return @taxes unless @taxes.nil?

      self.refresh_with_expanded_tax_rates

      @taxes = @invoice.total_tax_amounts
        .sort_by(&:inclusive)
        .reverse
        .map { |tax_amount| Tax.new(tax_amount.amount, @invoice.currency, tax_amount.tax_rate) }

      @taxes
    end

    # Determine if the customer is not exempted from taxes.
    def is_not_tax_exempt
      @invoice[:customer_tax_exempt] == 'none'
    end

    # Determine if the customer is exempted from taxes.
    def is_tax_exempt
      @invoice[:customer_tax_exempt] == 'exempt'
    end

    # Determine if reverse charge applies to the customer.
    def reverse_charge_applies
      @invoice[:customer_tax_exempt] == 'reverse'
    end

    # Get all of the "invoice item" line items.
    def invoice_items
      self.invoice_line_items_by_type('invoiceitem')
    end

    # Get all of the "subscription" line items.
    def subscriptions
      self.invoice_line_items_by_type('subscription')
    end

    # Get all of the invoice items by a given type.
    def invoice_line_items_by_type(type)
      if @items.nil?
        self.refresh_with_expanded_tax_rates

        @items = @invoice.lines.auto_paging_each
      end

      @items
        .select { |item| item.type == type }
        .map { |item| InvoiceLineItem.new(self, item) }
    end

    # Void the Stripe invoice.
    def void(options = {})
      @invoice = @invoice.void_invoice(options, @owner.stripe_options)

      self
    end

    # Get the Stripe model instance.
    def owner
      @owner
    end

    # Get the Stripe invoice instance.
    def as_stripe_invoice
      @invoice
    end

    # Dynamically get values from the Stripe invoice.
    def method_missing(key)
      @invoice[key]
    end

    protected

    # Refresh the invoice with expanded TaxRate objects.
    def refresh_with_expanded_tax_rates
      if @invoice.id
        @invoice = Stripe::Invoice.retrieve({
          :id => @invoice.id,
          :expand => [
            'lines.data.tax_amounts.tax_rate',
            'total_tax_amounts.tax_rate',
          ],
        }, @owner.stripe_options)
      else
        # If no invoice ID is present then assume this is the customer's upcoming invoice...
        @invoice = Stripe::Invoice.upcoming({
          :customer => @owner.stripe_id,
          :expand => [
            'lines.data.tax_amounts.tax_rate',
            'total_tax_amounts.tax_rate',
          ],
        }, @owner.stripe_options)
      end
    end

    # Format the given amount into a displayable currency.
    def format_amount(amount)
      Reji.format_amount(amount, @invoice.currency)
    end
  end
end
