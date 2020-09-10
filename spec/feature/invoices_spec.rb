# frozen_string_literal: true

require 'spec_helper'

describe 'invoices', type: :request do
  it 'test_require_stripe_customer_for_invoicing' do
    user = create_customer('require_stripe_customer_for_invoicing')

    expect do
      user.invoice
    end.to raise_error(Reji::InvalidCustomerError)
  end

  it 'test_invoicing_fails_with_nothing_to_invoice' do
    user = create_customer('invoicing_fails_with_nothing_to_invoice')
    user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')

    response = user.invoice

    expect(response).to be false
  end

  it 'test_customer_can_be_invoiced' do
    user = create_customer('customer_can_be_invoiced')
    user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')

    response = user.invoice_for('Rails Reji', 1000)

    expect(response).to be_an_instance_of(Reji::Invoice)
    expect(response.raw_total).to eq(1000)
  end

  it 'test_find_invoice_by_id' do
    user = create_customer('find_invoice_by_id')
    user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')

    invoice = user.invoice_for('Rails Reji', 1000)

    invoice = user.find_invoice(invoice.id)

    expect(invoice).to be_an_instance_of(Reji::Invoice)
    expect(invoice.raw_total).to eq(1000)
  end

  it 'throws_an_exception_if_the_invoice_does_not_belong_to_the_user' do
    user = create_customer('it_throws_an_exception_if_the_invoice_does_not_belong_to_the_user')
    user.create_as_stripe_customer
    other_user = create_customer('other_user')
    other_user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')
    invoice = user.invoice_for('Rails Reji', 1000)

    expect do
      other_user.find_invoice(invoice.id)
    end.to raise_error(Reji::InvalidInvoiceError, "The invoice `#{invoice.id}` does not belong to this customer `#{other_user.stripe_id}`.")
  end

  it 'test_find_invoice_by_id_or_fail' do
    user = create_customer('find_invoice_by_id_or_fail')
    user.create_as_stripe_customer
    other_user = create_customer('other_user')
    other_user.create_as_stripe_customer
    user.update_default_payment_method('pm_card_visa')
    invoice = user.invoice_for('Rails Reji', 1000)

    expect do
      other_user.find_invoice_or_fail(invoice.id)
    end.to raise_error(Reji::AccessDeniedHttpError)
  end
end
