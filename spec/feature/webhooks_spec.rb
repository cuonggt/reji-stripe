# frozen_string_literal: true

require 'spec_helper'

describe 'webhooks', type: :request do
  before(:all) do
    @product_id = "#{stripe_prefix}product-1-#{SecureRandom.hex(5)}"
    @plan_id = "#{stripe_prefix}monthly-10-#{SecureRandom.hex(5)}"

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
  end

  after(:all) do
    delete_stripe_resource(Stripe::Plan.retrieve(@plan_id))
    delete_stripe_resource(Stripe::Product.retrieve(@product_id))
  end

  it 'test_subscriptions_are_updated' do
    user = create_customer('subscriptions_are_updated', {:stripe_id => 'cus_foo'})

    subscription = user.subscriptions.create({
      :name => 'main',
      :stripe_id => 'sub_foo',
      :stripe_plan => 'plan_foo',
      :stripe_status => 'active',
    })

    item = subscription.items.create({
      :stripe_id => 'it_foo',
      :stripe_plan => 'plan_bar',
      :quantity => 1,
    })

    post '/stripe/webhook', :params => {
      :id => 'foo',
      :type => 'customer.subscription.updated',
      :data => {
        :object => {
          :id => subscription.stripe_id,
          :customer => 'cus_foo',
          :cancel_at_period_end => false,
          :quantity => 5,
          :items => {
            :data => [
              {
                :id => 'bar',
                :plan => {:id => 'plan_foo'},
                :quantity => 10,
              }
            ],
          },
        },
      },
    }.to_json, :headers => { 'CONTENT_TYPE' => 'application/json' }

    expect(response.status).to eq(200)

    expect(Reji::Subscription.where({
      :id => subscription.id,
      :user_id => user.id,
      :stripe_id => 'sub_foo',
      :quantity => 5,
    }).exists?).to be true

    expect(Reji::SubscriptionItem.where({
      :subscription_id => subscription.id,
      :stripe_id => 'bar',
      :stripe_plan => 'plan_foo',
      :quantity => 10,
    }).exists?).to be true

    expect(Reji::SubscriptionItem.where({
      :id => item.id,
    }).exists?).to be false
  end

  it 'test_cancelled_subscription_is_properly_reactivated' do
    user = create_customer('cancelled_subscription_is_properly_reactivated')
    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')
    subscription.cancel

    expect(subscription.cancelled).to be true

    post '/stripe/webhook', :params => {
      :id => 'foo',
      :type => 'customer.subscription.updated',
      :data => {
        :object => {
          :id => subscription.stripe_id,
          :customer => user.stripe_id,
          :cancel_at_period_end => false,
          :quantity => 1,
        },
      },
    }.to_json, :headers => { 'CONTENT_TYPE' => 'application/json' }

    expect(response.status).to eq(200)

    expect(subscription.reload.cancelled).to be false
  end

  it 'test_subscription_is_marked_as_cancelled_when_deleted_in_stripe' do
    user = create_customer('subscription_is_marked_as_cancelled_when_deleted_in_stripe')
    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    expect(subscription.cancelled).to be false

    post '/stripe/webhook', :params => {
      :id => 'foo',
      :type => 'customer.subscription.deleted',
      :data => {
        :object => {
          :id => subscription.stripe_id,
          :customer => user.stripe_id,
          :quantity => 1,
        },
      },
    }.to_json, :headers => { 'CONTENT_TYPE' => 'application/json' }

    expect(response.status).to eq(200)

    expect(subscription.reload.cancelled).to be true
  end

  it 'test_subscription_is_deleted_when_status_is_incomplete_expired' do
    user = create_customer('subscription_is_deleted_when_status_is_incomplete_expired')
    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    expect(user.subscriptions.count).to eq(1)

    post '/stripe/webhook', :params => {
      :id => 'foo',
      :type => 'customer.subscription.updated',
      :data => {
        :object => {
          :id => subscription.stripe_id,
          :customer => user.stripe_id,
          :status => 'incomplete_expired',
          :quantity => 1,
        },
      },
    }.to_json, :headers => { 'CONTENT_TYPE' => 'application/json' }

    expect(response.status).to eq(200)

    expect(user.reload.subscriptions.empty?).to be true
  end
end
