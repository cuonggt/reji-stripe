# frozen_string_literal: true

require 'spec_helper'

describe 'customer', type: :unit do
  it 'test_customer_can_be_put_on_a_generic_trial' do
    user = User.new

    expect(user.on_generic_trial).to be false

    user.trial_ends_at = Time.now + 1.day

    expect(user.on_generic_trial).to be true

    user.trial_ends_at = Time.now - 5.days

    expect(user.on_generic_trial).to be false
  end

  it 'test_we_can_determine_if_it_has_a_payment_method' do
    user = User.new

    user.card_brand = 'visa'

    expect(user.has_default_payment_method).to be true

    user = User.new

    expect(user.has_default_payment_method).to be false
  end

  it 'test_default_payment_method_returns_nil_when_the_user_is_not_a_customer_yet' do
    user = User.new

    expect(user.default_payment_method).to be_nil
  end

  it 'test_stripe_customer_method_throws_exception_when_stripe_id_is_not_set' do
    user = User.new

    expect {
      user.as_stripe_customer
    }.to raise_error(Reji::InvalidCustomerError)
  end

  it 'test_stripe_customer_cannot_be_created_when_stripe_id_is_already_set' do
    user = User.new
    user.stripe_id = 'foo'

    expect {
      user.create_as_stripe_customer
    }.to raise_error(Reji::CustomerAlreadyCreatedError)
  end
end
