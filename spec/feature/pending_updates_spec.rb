# frozen_string_literal: true

require 'spec_helper'

describe 'pending updates', type: :request do
  before(:all) do
    @product_id = "#{stripe_prefix}product-1-#{SecureRandom.hex(5)}"
    @plan_id = "#{stripe_prefix}monthly-10-#{SecureRandom.hex(5)}"
    @other_plan_id = "#{stripe_prefix}monthly-10-#{SecureRandom.hex(5)}"
    @premium_plan_id = "#{stripe_prefix}monthly-20-premium-#{SecureRandom.hex(5)}"

    Stripe::Product.create({
      :id => @product_id,
      :name => 'Rails Reji Test Product',
      :type => 'service',
    })

    Stripe::Plan.create({
      :id => @plan_id,
      :nickname => 'Monthly $10',
      :currency => 'USD',
      :interval => 'month',
      :billing_scheme => 'per_unit',
      :amount => 1000,
      :product => @product_id,
    })

    Stripe::Plan.create({
      :id => @other_plan_id,
      :nickname => 'Monthly $10 Other',
      :currency => 'USD',
      :interval => 'month',
      :billing_scheme => 'per_unit',
      :amount => 1000,
      :product => @product_id,
    })

    Stripe::Plan.create({
      :id => @premium_plan_id,
      :nickname => 'Monthly $20 Premium',
      :currency => 'USD',
      :interval => 'month',
      :billing_scheme => 'per_unit',
      :amount => 2000,
      :product => @product_id,
    })
  end

  after(:all) do
    delete_stripe_resource(Stripe::Plan.retrieve(@plan_id))
    delete_stripe_resource(Stripe::Plan.retrieve(@other_plan_id))
    delete_stripe_resource(Stripe::Plan.retrieve(@premium_plan_id))
    delete_stripe_resource(Stripe::Product.retrieve(@product_id))
  end

  it 'test_subscription_can_error_if_incomplete' do
    user = create_customer('subscription_can_error_if_incomplete')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    # Set a faulty card as the customer's default payment method.
    user.update_default_payment_method('pm_card_threeDSecure2Required')

    begin
      # Attempt to swap and pay with a faulty card.
      subscription = subscription.error_if_payment_fails.swap_and_invoice(@premium_plan_id)

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentFailureError was not thrown.')
    rescue Stripe::CardError => e
      # Assert that the plan was not swapped.
      expect(subscription.stripe_plan).to eq(@plan_id)

      # Assert subscription is active.
      expect(subscription.active).to be true
    end
  end
end
