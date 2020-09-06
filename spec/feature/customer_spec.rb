# frozen_string_literal: true

require 'spec_helper'

describe 'customer', type: :feature do
  it 'test_customers_in_stripe_can_be_updated' do
    user = create_customer('customers_in_stripe_can_be_updated')
    user.create_as_stripe_customer

    customer = user.update_stripe_customer({:description => 'Van Cam'})

    expect(customer.description).to eq('Van Cam')
  end

  # it 'test_customers_can_generate_a_billing_portal_url' do
  #   user = create_customer('customers_in_stripe_can_be_updated')
  #   user.create_as_stripe_customer

  #   url = user.billing_portal_url('https://example.com')

  #   expect(url).to start_with('https://billing.stripe.com/session/')
  # end
end
