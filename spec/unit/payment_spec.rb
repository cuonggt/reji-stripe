# frozen_string_literal: true

require 'spec_helper'

describe 'payment' do
  it 'can_return_its_requires_payment_method_status' do
    payment_intent = Stripe::PaymentIntent.new
    payment_intent.status = 'requires_payment_method'
    payment = Reji::Payment.new(payment_intent)
    expect(payment.requires_payment_method).to be true
  end

  it 'can_return_its_requires_action_status' do
    payment_intent = Stripe::PaymentIntent.new
    payment_intent.status = 'requires_action'
    payment = Reji::Payment.new(payment_intent)
    expect(payment.requires_action).to be true
  end

  it 'can_return_its_cancelled_status' do
    payment_intent = Stripe::PaymentIntent.new
    payment_intent.status = 'canceled'
    payment = Reji::Payment.new(payment_intent)
    expect(payment.is_cancelled).to be true
  end

  it 'can_return_its_succeeded_status' do
    payment_intent = Stripe::PaymentIntent.new
    payment_intent.status = 'succeeded'
    payment = Reji::Payment.new(payment_intent)
    expect(payment.is_succeeded).to be true
  end
end
