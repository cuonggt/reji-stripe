# frozen_string_literal: true

require 'spec_helper'

describe 'invoice', type: :unit do
  it 'can_return_the_invoice_date' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.created = 1560541724

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    date = invoice.date

    expect(invoice.date.to_i).to eq(1560541724)
  end

  it 'can_return_its_total' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.total = 1000
    stripe_invoice.currency = 'USD'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.total).to eq('$10.00')
  end

  it 'can_return_its_raw_total' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.total = 1000
    stripe_invoice.currency = 'USD'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.raw_total).to eq(1000)
  end

  it 'returns_a_lower_total_when_there_was_a_starting_balance' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.total = 1000
    stripe_invoice.currency = 'USD'
    stripe_invoice.starting_balance = -450

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.total).to eq('$5.50')
  end

  it 'can_return_its_subtotal' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.subtotal = 500
    stripe_invoice.currency = 'USD'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.subtotal).to eq('$5.00')
  end

  it 'can_determine_when_the_customer_has_a_starting_balance' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.starting_balance = -450

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.has_starting_balance).to be true
  end

  it 'can_determine_when_the_customer_does_not_have_a_starting_balance' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.starting_balance = 0

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.has_starting_balance).to be false
  end

  it 'can_return_its_starting_balance' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.starting_balance = -450
    stripe_invoice.currency = 'USD'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.starting_balance).to eq('$-4.50')
  end

  it 'can_return_its_raw_starting_balance' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.starting_balance = -450
    stripe_invoice.currency = 'USD'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.raw_starting_balance).to eq(-450)
  end

  it 'can_determine_if_it_has_a_discount_applied' do
    coupon = Stripe::Coupon.new
    coupon.amount_off = 50

    discount = Stripe::Discount.new
    discount.coupon = coupon

    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.subtotal = 450
    stripe_invoice.total = 500
    stripe_invoice.discount = discount

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.has_discount).to be true
  end

  it 'can_return_its_tax' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.tax = 50
    stripe_invoice.currency = 'USD'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.tax).to eq('$0.50')
  end

  it 'can_determine_if_the_customer_was_exempt_from_taxes' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.customer_tax_exempt = 'exempt'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.is_tax_exempt).to be true
  end

  it 'can_determine_if_reverse_charge_applies' do
    stripe_invoice = Stripe::Invoice.new
    stripe_invoice.customer = 'foo'
    stripe_invoice.customer_tax_exempt = 'reverse'

    user = User.new
    user.stripe_id = 'foo'

    invoice = Reji::Invoice.new(user, stripe_invoice)

    expect(invoice.reverse_charge_applies).to be true
  end
end
