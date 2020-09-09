# frozen_string_literal: true

require 'spec_helper'

describe 'charges', type: :request do
  it 'test_customer_can_be_charged' do
    user = create_customer('customer_can_be_charged')
    user.create_as_stripe_customer

    response = user.charge(1000, 'pm_card_visa')

    expect(response).to be_an_instance_of(Reji::Payment)
    expect(response.raw_amount).to eq(1000)
    expect(response.customer).to eq(user.stripe_id)
  end

  it 'test_non_stripe_customer_can_be_charged' do
    user = create_customer('non_stripe_customer_can_be_charged')

    response = user.charge(1000, 'pm_card_visa')

    expect(response).to be_an_instance_of(Reji::Payment)
    expect(response.raw_amount).to eq(1000)
    expect(response.customer).to eq(user.stripe_id)
  end

  it 'test_customer_can_be_charged_and_invoiced_immediately' do
    user = create_customer('customer_can_be_charged_and_invoiced_immediately')
    user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')

    user.invoice_for('Rails Reji', 1000)

    invoice = user.invoices.first

    expect(invoice.total).to eq('$10.00')
    expect(invoice.invoice_items.first.as_stripe_invoice_line_item.description).to eq('Rails Reji')
  end

  it 'test_customer_can_be_refunded' do
    user = create_customer('customer_can_be_refunded')
    user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')

    invoice = user.invoice_for('Rails Reji', 1000)
    refund = user.refund(invoice.payment_intent)

    expect(refund.amount).to eq(1000)
  end

  it 'test_charging_may_require_an_extra_action' do
    user = create_customer('charging_may_require_an_extra_action')
    user.create_as_stripe_customer

    begin
      user.charge(1000, 'pm_card_threeDSecure2Required')

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentActionRequiredError was not thrown.')
    rescue Reji::PaymentActionRequiredError => e
      # Assert that the payment needs an extra action.
      expect(e.payment.requires_action).to be true

      # Assert that the payment was for the correct amount.
      expect(e.payment.raw_amount).to eq(1000)
    end
  end
end
