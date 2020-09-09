# frozen_string_literal: true

require 'spec_helper'

describe 'payment_methods', type: :request do
  it 'test_we_can_start_a_new_setup_intent_session' do
    user = create_customer('we_can_start_a_new_setup_intent_session')
    setup_intent = user.create_setup_intent
    expect(setup_intent).to be_an_instance_of(Stripe::SetupIntent)
  end

  it 'test_we_can_add_payment_methods' do
    user = create_customer('we_can_add_payment_methods')
    user.create_as_stripe_customer

    payment_method = user.add_payment_method('pm_card_visa')

    expect(payment_method).to be_an_instance_of(Reji::PaymentMethod)
    expect(payment_method.card.brand).to eq('visa')
    expect(payment_method.card.last4).to eq('4242')
    expect(user.has_payment_method).to be true
    expect(user.has_default_payment_method).to be false
  end

  it 'test_we_can_remove_payment_methods' do
    user = create_customer('we_can_remove_payment_methods')
    user.create_as_stripe_customer

    payment_method = user.add_payment_method('pm_card_visa')

    expect(user.payment_methods.count).to eq(1)
    expect(user.has_payment_method).to be true

    user.remove_payment_method(payment_method.as_stripe_payment_method)

    expect(user.payment_methods.count).to eq(0)
    expect(user.has_payment_method).to be false
  end

  it 'test_we_can_remove_the_default_payment_method' do
    user = create_customer('we_can_remove_the_default_payment_method')
    user.create_as_stripe_customer

    payment_method = user.update_default_payment_method('pm_card_visa')

    expect(user.payment_methods.count).to eq(1)
    expect(user.has_payment_method).to be true
    expect(user.has_default_payment_method).to be true

    user.remove_payment_method(payment_method.as_stripe_payment_method)

    expect(user.payment_methods.count).to eq(0)
    expect(user.default_payment_method).to be_nil
    expect(user.card_brand).to be_nil
    expect(user.card_last_four).to be_nil
    expect(user.has_payment_method).to be false
    expect(user.has_default_payment_method).to be false
  end

  it 'test_we_can_set_a_default_payment_method' do
    user = create_customer('we_can_set_a_default_payment_method')
    user.create_as_stripe_customer

    payment_method = user.update_default_payment_method('pm_card_visa')

    expect(payment_method).to be_an_instance_of(Reji::PaymentMethod)
    expect(payment_method.card.brand).to eq('visa')
    expect(payment_method.card.last4).to eq('4242')
    expect(user.has_default_payment_method).to be true

    payment_method = user.default_payment_method

    expect(payment_method).to be_an_instance_of(Reji::PaymentMethod)
    expect(payment_method.card.brand).to eq('visa')
    expect(payment_method.card.last4).to eq('4242')
  end

  it 'test_legacy_we_can_retrieve_an_old_default_source_as_a_default_payment_method' do
    user = create_customer('we_can_retrieve_an_old_default_source_as_a_default_payment_method')
    customer = user.create_as_stripe_customer
    card = Stripe::Customer.create_source(customer.id, {:source => 'tok_visa'}, user.stripe_options)
    customer.default_source = card.id
    customer.save

    payment_method = user.default_payment_method

    expect(payment_method).to be_an_instance_of(Stripe::Card)
    expect(payment_method.brand).to eq('Visa')
    expect(payment_method.last4).to eq('4242')
  end

  it 'test_we_can_retrieve_all_payment_methods' do
    user = create_customer('we_can_retrieve_all_payment_methods')
    customer = user.create_as_stripe_customer

    payment_method = Stripe::PaymentMethod.retrieve('pm_card_visa', user.stripe_options)
    payment_method.attach({:customer => customer.id})

    payment_method = Stripe::PaymentMethod.retrieve('pm_card_mastercard', user.stripe_options)
    payment_method.attach({:customer => customer.id})

    payment_methods = user.payment_methods

    expect(payment_methods.count).to eq(2)
    expect(payment_methods.first.card.brand).to eq('mastercard')
    expect(payment_methods.last.card.brand).to eq('visa')
  end

  it 'test_we_can_sync_the_default_payment_method_from_stripe' do
    user = create_customer('we_can_sync_the_payment_method_from_stripe')
    customer = user.create_as_stripe_customer

    payment_method = Stripe::PaymentMethod.retrieve('pm_card_visa', user.stripe_options)
    payment_method.attach({:customer => customer.id})

    customer.invoice_settings = {:default_payment_method => payment_method.id}

    customer.save

    expect(user.card_brand).to be_nil
    expect(user.card_last_four).to be_nil

    user.update_default_payment_method_from_stripe

    expect(user.card_brand).to eq('visa')
    expect(user.card_last_four).to eq('4242')
  end

  it 'test_we_delete_all_payment_methods' do
    user = create_customer('we_delete_all_payment_methods')
    customer = user.create_as_stripe_customer

    payment_method = Stripe::PaymentMethod.retrieve('pm_card_visa', user.stripe_options)
    payment_method.attach({:customer => customer.id})

    payment_method = Stripe::PaymentMethod.retrieve('pm_card_mastercard', user.stripe_options)
    payment_method.attach({:customer => customer.id})

    payment_methods = user.payment_methods

    expect(payment_methods.count).to eq(2)

    user.delete_payment_methods

    payment_methods = user.payment_methods

    expect(payment_methods.count).to eq(0)
  end
end
