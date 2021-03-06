# frozen_string_literal: true

require 'spec_helper'

describe 'invoice line item' do
  it 'can_calculate_the_inclusive_tax_percentage' do
    customer = User.new
    customer.stripe_id = 'foo'

    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer_tax_exempt = 'none'
    stripe_invoice.customer = 'foo'

    invoice = Reji::Invoice.new(customer, stripe_invoice)

    stripe_invoice_line_item = Stripe::InvoiceLineItem.new
    stripe_invoice_line_item.tax_amounts = [
      { inclusive: true, tax_rate: inclusive_tax_rate(5.0) },
      { inclusive: true, tax_rate: inclusive_tax_rate(15.0) },
      { inclusive: false, tax_rate: inclusive_tax_rate(21.0) },
    ]

    item = Reji::InvoiceLineItem.new(invoice, stripe_invoice_line_item)

    expect(item.inclusive_tax_percentage).to eq(20)
  end

  it 'can_calculate_the_exclusive_tax_percentage' do
    customer = User.new
    customer.stripe_id = 'foo'

    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer_tax_exempt = 'none'
    stripe_invoice.customer = 'foo'

    invoice = Reji::Invoice.new(customer, stripe_invoice)

    stripe_invoice_line_item = Stripe::InvoiceLineItem.new
    stripe_invoice_line_item.tax_amounts = [
      { inclusive: true, tax_rate: inclusive_tax_rate(5.0) },
      { inclusive: false, tax_rate: exclusive_tax_rate(15.0) },
      { inclusive: false, tax_rate: exclusive_tax_rate(21.0) },
    ]

    item = Reji::InvoiceLineItem.new(invoice, stripe_invoice_line_item)

    result = item.exclusive_tax_percentage

    expect(result).to eq(36)
  end

  # Get a test inclusive Tax Rate.
  protected def inclusive_tax_rate(percentage)
    tax_rate(percentage)
  end

  # Get a test exclusive Tax Rate.
  protected def exclusive_tax_rate(percentage)
    tax_rate(percentage, false)
  end

  # Get a test exclusive Tax Rate.
  protected def tax_rate(percentage, inclusive = true)
    inclusive_tax_rate = Stripe::TaxRate.new
    inclusive_tax_rate.inclusive = inclusive
    inclusive_tax_rate.percentage = percentage

    inclusive_tax_rate
  end
end
