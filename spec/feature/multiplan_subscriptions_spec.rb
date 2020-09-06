# frozen_string_literal: true

require 'spec_helper'

describe 'multiplan subscriptions', type: :feature do
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

    @tax_rate_id = Stripe::TaxRate.create({
      :display_name => 'VAT',
      :description => 'VAT Belgium',
      :jurisdiction => 'BE',
      :percentage => 21,
      :inclusive => false,
    }).id
  end

  after(:all) do
    delete_stripe_resource(Stripe::Plan.retrieve(@plan_id))
    delete_stripe_resource(Stripe::Plan.retrieve(@other_plan_id))
    delete_stripe_resource(Stripe::Plan.retrieve(@premium_plan_id))
    delete_stripe_resource(Stripe::Product.retrieve(@product_id))
  end

  it 'test_customers_can_have_multiplan_subscriptions' do
    user = create_customer('customers_can_have_multiplan_subscriptions')

    user.plan_tax_rates = {@other_plan_id => [@tax_rate_id]}

    subscription = user.new_subscription('main', [@plan_id, @other_plan_id])
      .plan(@premium_plan_id, 5)
      .quantity(10, @plan_id)
      .create('pm_card_visa')

    expect(user.subscribed('main', @plan_id)).to be true
    expect(user.on_plan(@plan_id)).to be true

    item = subscription.find_item_or_fail(@plan_id)
    other_item = subscription.find_item_or_fail(@other_plan_id)
    premium_item = subscription.find_item_or_fail(@premium_plan_id)

    expect(subscription.items.count).to eq(3)
    expect(item.stripe_plan).to eq(@plan_id)
    expect(item.quantity).to eq(10)
    expect(other_item.stripe_plan).to eq(@other_plan_id)
    expect(other_item.quantity).to eq(1)
    expect(premium_item.stripe_plan).to eq(@premium_plan_id)
    expect(premium_item.quantity).to eq(5)
  end

  it 'test_customers_can_add_plans' do
    user = create_customer('customers_can_add_plans')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    subscription.add_plan(@other_plan_id, 5)

    expect(user.on_plan(@plan_id)).to be true
    expect(user.on_plan(@premium_plan_id)).to be false

    item = subscription.find_item_or_fail(@plan_id)
    other_item = subscription.find_item_or_fail(@other_plan_id)

    expect(subscription.items.count).to eq(2)
    expect(item.stripe_plan).to eq(@plan_id)
    expect(item.quantity).to eq(1)
    expect(other_item.stripe_plan).to eq(@other_plan_id)
    expect(other_item.quantity).to eq(5)
  end

  it 'test_customers_can_remove_plans' do
    user = create_customer('customers_can_remove_plans')

    subscription = user.new_subscription(
      'main', [@plan_id, @other_plan_id]
    ).create('pm_card_visa')

    expect(subscription.items.count).to eq(2)

    subscription.remove_plan(@plan_id)

    expect(subscription.items.count).to eq(1)
  end

  it 'test_customers_cannot_remove_the_last_plan' do
    user = create_customer('customers_cannot_remove_the_last_plan')

    subscription = self.create_subscription_with_single_plan(user)

    expect {
      subscription.remove_plan(@plan_id)
    }.to raise_error(Reji::SubscriptionUpdateFailureError)
  end

  it 'test_multiplan_subscriptions_can_be_resumed' do
    user = create_customer('multiplan_subscriptions_can_be_resumed')

    subscription = user.new_subscription(
      'main', [@plan_id, @other_plan_id]
    ).create('pm_card_visa')

    subscription.cancel

    expect(subscription.active).to be true
    expect(subscription.on_grace_period).to be true

    subscription.resume

    expect(subscription.active).to be true
    expect(subscription.on_grace_period).to be false
  end

  it 'test_plan_is_required_when_updating_quantities_for_multiplan_subscriptions' do
    user = create_customer('plan_is_required_when_updating_quantities_for_multiplan_subscriptions')

    subscription = self.create_subscription_with_multiple_plans(user)

    expect {
      subscription.update_quantity(5)
    }.to raise_error(ArgumentError)
  end

  it 'test_subscription_item_quantities_can_be_updated' do
    user = create_customer('subscription_item_quantities_can_be_updated')

    subscription = user.new_subscription(
      'main', [@plan_id, @other_plan_id]
    ).create('pm_card_visa')

    subscription.update_quantity(5, @other_plan_id)

    item = subscription.find_item_or_fail(@other_plan_id)

    expect(item.quantity).to eq(5)
  end

  it 'test_subscription_item_quantities_can_be_incremented' do
    user = create_customer('subscription_item_quantities_can_be_incremented')

    subscription = user.new_subscription(
      'main', [@plan_id, @other_plan_id]
    ).create('pm_card_visa')

    subscription.increment_quantity(3, @other_plan_id)

    item = subscription.find_item_or_fail(@other_plan_id)

    expect(item.quantity).to eq(4)

    item.increment_quantity(3)

    expect(item.quantity).to eq(7)
  end

  it 'test_subscription_item_quantities_can_be_decremented' do
    user = create_customer('subscription_item_quantities_can_be_decremented')

    subscription = user.new_subscription(
      'main', [@plan_id, @other_plan_id]
    ).quantity(5, @other_plan_id).create('pm_card_visa')

    subscription.decrement_quantity(2, @other_plan_id)

    item = subscription.find_item_or_fail(@other_plan_id)

    expect(item.quantity).to eq(3)

    item.decrement_quantity(2)

    expect(item.quantity).to eq(1)
  end

  it 'test_multiple_plans_can_be_swapped' do
    user = create_customer('multiple_plans_can_be_swapped')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    subscription.swap([@other_plan_id, @premium_plan_id])

    plans = subscription.items.pluck(:stripe_plan)

    expect(plans.count).to eq(2)
    expect(plans).to contain_exactly(@other_plan_id, @premium_plan_id)
  end

  it 'test_subscription_items_can_swap_plans' do
    user = create_customer('subscription_items_can_swap_plans')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    item = subscription.items.first.swap(@other_plan_id, {:quantity => 3})

    expect(subscription.items.count).to eq(1)
    expect(subscription.stripe_plan).to eq(@other_plan_id)
    expect(item.stripe_plan).to eq(@other_plan_id)
    expect(item.quantity).to eq(3)
  end

  it 'test_subscription_item_changes_can_be_prorated' do
    user = create_customer('subscription_item_changes_can_be_prorated')

    subscription = user.new_subscription('main', @premium_plan_id).create('pm_card_visa')

    invoice = user.invoices.first

    expect(invoice.raw_total).to eq(2000)

    subscription.no_prorate.add_plan(@other_plan_id)

    # Assert that no new invoice was created because of no prorating.
    expect(user.invoices.first.id).to eq(invoice.id)

    subscription.add_plan_and_invoice(@plan_id)

    # Assert that a new invoice was created because of no prorating.
    invoice = user.invoices.first
    expect(invoice.raw_total).to eq(1000)
    expect(user.upcoming_invoice.raw_total).to eq(4000)

    subscription.no_prorate.remove_plan(@premium_plan_id)

    # Assert that no new invoice was created because of no prorating.
    expect(user.invoices.first.id).to eq(invoice.id)
    expect(user.upcoming_invoice.raw_total).to eq(2000)
  end

  it 'test_subscription_item_quantity_changes_can_be_prorated' do
    user = create_customer('subscription_item_quantity_changes_can_be_prorated')

    subscription = user.new_subscription('main', [@plan_id, @other_plan_id])
      .quantity(3, @other_plan_id)
      .create('pm_card_visa')

    invoice = user.invoices.first

    expect(invoice.raw_total).to eq(4000)

    subscription.no_prorate.update_quantity(1, @other_plan_id)

    expect(user.upcoming_invoice.raw_total).to eq(2000)
  end

  protected

  # Create a subscription with a single plan.
  def create_subscription_with_single_plan(user)
    subscription = user.subscriptions.create({
      :name => 'main',
      :stripe_id => 'sub_foo',
      :stripe_plan => @plan_id,
      :quantity => 1,
      :stripe_status => 'active',
    })

    subscription.items.create({
      :stripe_id => 'it_foo',
      :stripe_plan => @plan_id,
      :quantity => 1,
    })

    subscription
  end

  # Create a subscription with multiple plans.
  def create_subscription_with_multiple_plans(user)
    subscription = self.create_subscription_with_single_plan(user)

    subscription.stripe_plan = nil
    subscription.quantity = nil
    subscription.save

    subscription.items.new({
      :stripe_id => 'it_foo',
      :stripe_plan => @other_plan_id,
      :quantity => 1,
    })

    subscription
  end
end
