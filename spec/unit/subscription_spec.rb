# frozen_string_literal: true

require 'spec_helper'

describe 'subscription' do
  it 'can_determine_if_it_is_incomplete' do
    subscription = Reji::Subscription.new(stripe_status: 'incomplete')

    expect(subscription.incomplete).to be true
    expect(subscription.past_due).to be false
    expect(subscription.active).to be false
  end

  it 'can_determine_if_it_is_past_due' do
    subscription = Reji::Subscription.new(stripe_status: 'past_due')
    expect(subscription.incomplete).to be false
    expect(subscription.past_due).to be true
    expect(subscription.active).to be false
  end

  it 'can_determine_if_it_is_active' do
    subscription = Reji::Subscription.new(stripe_status: 'active')

    expect(subscription.incomplete).to be false
    expect(subscription.past_due).to be false
    expect(subscription.active).to be true
  end

  it 'is_not_valid_when_status_is_incomplete' do
    subscription = Reji::Subscription.new(stripe_status: 'incomplete')

    expect(subscription.valid).to be false
  end

  it 'is_not_valid_when_status_is_past_due' do
    subscription = Reji::Subscription.new(stripe_status: 'past_due')

    expect(subscription.valid).to be false
  end

  it 'is_valid_when_status_is_active' do
    subscription = Reji::Subscription.new(stripe_status: 'active')

    expect(subscription.valid).to be true
  end

  it 'has_incomplete_payment_when_status_is_incomplete' do
    subscription = Reji::Subscription.new(stripe_status: 'incomplete')

    expect(subscription.has_incomplete_payment).to be true
  end

  it 'has_incomplete_payment_when_status_is_past_due' do
    subscription = Reji::Subscription.new(stripe_status: 'past_due')

    expect(subscription.has_incomplete_payment).to be true
  end

  it 'has_not_incomplete_payment_when_status_is_active' do
    subscription = Reji::Subscription.new(stripe_status: 'active')

    expect(subscription.has_incomplete_payment).to be false
  end

  it 'cannot_swap_when_it_is_incomplete' do
    subscription = Reji::Subscription.new(stripe_status: 'incomplete')

    expect {
      subscription.swap('premium_plan')
    }.to raise_error(Reji::SubscriptionUpdateFailureError)
  end

  it 'cannot_update_their_quantity_when_it_is_incomplete' do
    subscription = Reji::Subscription.new(stripe_status: 'incomplete')

    expect {
      subscription.update_quantity(5)
    }.to raise_error(Reji::SubscriptionUpdateFailureError)
  end

  it 'requires_a_date_in_the_future_when_extending_a_trial' do
    subscription = Reji::Subscription.new

    expect {
      subscription.extend_trial(Time.now - 1.day)
    }.to raise_error(ArgumentError)
  end

  it 'can_determine_if_it_has_a_single_plan' do
    subscription = Reji::Subscription.new(stripe_plan: 'foo')

    expect(subscription.has_single_plan).to be true
    expect(subscription.has_multiple_plans).to be false
  end

  it 'can_determine_if_it_has_multiple_plans' do
    subscription = Reji::Subscription.new(stripe_plan: nil)

    expect(subscription.has_single_plan).to be false
    expect(subscription.has_multiple_plans).to be true
  end
end
