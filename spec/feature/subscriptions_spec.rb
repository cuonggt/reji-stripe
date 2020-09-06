# frozen_string_literal: true

require 'spec_helper'

describe 'subscriptions', type: :feature do
  before(:all) do
    @product_id = "#{stripe_prefix}product-1-#{SecureRandom.hex(5)}"
    @plan_id = "#{stripe_prefix}monthly-10-#{SecureRandom.hex(5)}"
    @other_plan_id = "#{stripe_prefix}monthly-10-#{SecureRandom.hex(5)}"
    @premium_plan_id = "#{stripe_prefix}monthly-20-premium-#{SecureRandom.hex(5)}"
    @coupon_id = "#{stripe_prefix}coupon-#{SecureRandom.hex(5)}"

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

    Stripe::Coupon.create({
      :id => @coupon_id,
      :duration => 'repeating',
      :amount_off => 500,
      :duration_in_months => 3,
      :currency => 'USD',
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
    delete_stripe_resource(Stripe::Coupon.retrieve(@coupon_id))
  end

  it 'test_subscriptions_can_be_created' do
    user = create_customer('subscriptions_can_be_created')

    # Create Subscription
    user.new_subscription('main', @plan_id).create('pm_card_visa')

    expect(user.subscriptions.count).to eq(1)
    expect(user.subscription('main').stripe_id).to_not be_nil

    expect(user.subscribed('main')).to be true
    expect(user.subscribed_to_plan(@plan_id, 'main')).to be true
    expect(user.subscribed_to_plan(@plan_id, 'something')).to be false
    expect(user.subscribed_to_plan(@other_plan_id, 'main')).to be false
    expect(user.subscribed('main', @plan_id)).to be true
    expect(user.subscribed('main', @other_plan_id)).to be false
    expect(user.subscription('main').active).to be true
    expect(user.subscription('main').cancelled).to be false
    expect(user.subscription('main').on_grace_period).to be false
    expect(user.subscription('main').recurring).to be true
    expect(user.subscription('main').ended).to be false

    # Cancel Subscription
    subscription = user.subscription('main')
    subscription.cancel

    expect(subscription.active).to be true
    expect(subscription.cancelled).to be true
    expect(subscription.on_grace_period).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false

    # Modify Ends Date To Past
    old_grace_period = subscription.ends_at
    subscription.update({:ends_at => Time.now - 5.days})

    expect(subscription.active).to be false
    expect(subscription.cancelled).to be true
    expect(subscription.on_grace_period).to be false
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be true

    subscription.update({:ends_at => old_grace_period})

    # Resume Subscription
    subscription.resume

    expect(subscription.active).to be true
    expect(subscription.cancelled).to be false
    expect(subscription.on_grace_period).to be false
    expect(subscription.recurring).to be true
    expect(subscription.ended).to be false

    # Increment & Decrement
    subscription.increment_quantity

    expect(subscription.quantity).to eq(2)

    subscription.decrement_quantity

    expect(subscription.quantity).to eq(1)

    # Swap Plan and invoice immediately.
    subscription.swap_and_invoice(@other_plan_id)

    expect(subscription.stripe_plan).to eq(@other_plan_id)

    # Invoice Tests
    invoice = user.invoices.last

    expect(invoice.total).to eq('$10.00')
    expect(invoice.has_discount).to be false
    expect(invoice.has_starting_balance).to be false
    expect(invoice.coupon).to be_nil
  end

  it 'test_swapping_subscription_with_coupon' do
    user = create_customer('swapping_subscription_with_coupon')
    user.new_subscription('main', @plan_id).create('pm_card_visa')
    subscription = user.subscription('main')

    subscription.swap(@other_plan_id, {:coupon => @coupon_id})

    expect(subscription.as_stripe_subscription.discount.coupon.id).to eq(@coupon_id)
  end

  it 'test_declined_card_during_subscribing_results_in_an_exception' do
    user = create_customer('declined_card_during_subscribing_results_in_an_exception')

    begin
      user.new_subscription('main', @plan_id).create('pm_card_chargeCustomerFail')

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentFailureError was not thrown.')
    rescue Reji::PaymentFailureError => e
      # Assert that the payment needs a valid payment method.
      expect(e.payment.requires_payment_method).to be true

      # Assert subscription was added to the billable entity.
      subscription = user.subscription('main')
      expect(subscription).to be_an_instance_of Reji::Subscription

      # Assert subscription is incomplete.
      expect(subscription.incomplete).to be true
    end
  end

  it 'test_next_action_needed_during_subscribing_results_in_an_exception' do
    user = create_customer('next_action_needed_during_subscribing_results_in_an_exception')

    begin
      user.new_subscription('main', @plan_id).create('pm_card_threeDSecure2Required')

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentActionRequiredError was not thrown.')
    rescue Reji::PaymentActionRequiredError => e
      # Assert that the payment needs an extra action.
      expect(e.payment.requires_action).to be true

      # Assert subscription was added to the billable entity.
      subscription = user.subscription('main')
      expect(subscription).to be_an_instance_of Reji::Subscription

      # Assert subscription is incomplete.
      expect(subscription.incomplete).to be true
    end
  end

  it 'test_declined_card_during_plan_swap_results_in_an_exception' do
    user = create_customer('declined_card_during_plan_swap_results_in_an_exception')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    # Set a faulty card as the customer's default payment method.
    user.update_default_payment_method('pm_card_chargeCustomerFail')

    begin
      # Attempt to swap and pay with a faulty card.
      subscription = subscription.swap_and_invoice(@premium_plan_id)

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentFailureError was not thrown.')
    rescue Reji::PaymentFailureError => e
      # Assert that the payment needs a valid payment method.
      expect(e.payment.requires_payment_method).to be true

      # Assert that the plan was swapped anyway.
      expect(subscription.stripe_plan).to eq(@premium_plan_id)

      # Assert subscription is past due.
      expect(subscription.past_due).to be true
    end
  end

  it 'test_next_action_needed_during_plan_swap_results_in_an_exception' do
    user = create_customer('next_action_needed_during_plan_swap_results_in_an_exception')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    # Set a card that requires a next action as the customer's default payment method.
    user.update_default_payment_method('pm_card_threeDSecure2Required')

    begin
      # Attempt to swap and pay with a faulty card.
      subscription = subscription.swap_and_invoice(@premium_plan_id)

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentActionRequiredError was not thrown.')
    rescue Reji::PaymentActionRequiredError => e
      # Assert that the payment needs an extra action.
      expect(e.payment.requires_action).to be true

      # Assert that the plan was swapped anyway.
      expect(subscription.stripe_plan).to eq(@premium_plan_id)

      # Assert subscription is past due.
      expect(subscription.past_due).to be true
    end
  end

  it 'test_downgrade_with_faulty_card_does_not_incomplete_subscription' do
    user = create_customer('downgrade_with_faulty_card_does_not_incomplete_subscription')

    subscription = user.new_subscription('main', @premium_plan_id).create('pm_card_visa')

    # Set a card that requires a next action as the customer's default payment method.
    user.update_default_payment_method('pm_card_chargeCustomerFail')

    # Attempt to swap and pay with a faulty card.
    subscription = subscription.swap(@plan_id)

    # Assert that the plan was swapped anyway.
    expect(subscription.stripe_plan).to eq(@plan_id)

    # Assert subscription is still active.
    expect(subscription.active).to be true
  end

  it 'test_downgrade_with_3d_secure_does_not_incomplete_subscription' do
    user = create_customer('downgrade_with_3d_secure_does_not_incomplete_subscription')

    subscription = user.new_subscription('main', @premium_plan_id).create('pm_card_visa')

    # Set a card that requires a next action as the customer's default payment method.
    user.update_default_payment_method('pm_card_threeDSecure2Required')

    # Attempt to swap and pay with a faulty card.
    subscription = subscription.swap(@plan_id)

    # Assert that the plan was swapped anyway.
    expect(subscription.stripe_plan).to eq(@plan_id)

    # Assert subscription is still active.
    expect(subscription.active).to be true
  end

  it 'test_creating_subscription_with_coupons' do
    user = create_customer('creating_subscription_with_coupons')

    # Create Subscription
    user.new_subscription('main', @plan_id)
      .with_coupon(@coupon_id)
      .create('pm_card_visa')

    subscription = user.subscription('main')

    expect(user.subscribed('main')).to be true
    expect(user.subscribed('main', @plan_id)).to be true
    expect(user.subscribed('main', @other_plan_id)).to be false
    expect(subscription.active).to be true
    expect(subscription.cancelled).to be false
    expect(subscription.on_grace_period).to be false
    expect(subscription.recurring).to be true
    expect(subscription.ended).to be false

    # Invoice Tests
    invoice = user.invoices.first

    expect(invoice.has_discount).to be true
    expect(invoice.total).to eq('$5.00')
    expect(invoice.amount_off).to eq('$5.00')
    expect(invoice.discount_is_percentage).to be false
  end

  it 'test_creating_subscription_with_an_anchored_billing_cycle' do
    user = create_customer('creating_subscription_with_an_anchored_billing_cycle')

    # Create Subscription
    user.new_subscription('main', @plan_id)
      .anchor_billing_cycle_on(Time.now.at_beginning_of_month.next_month.to_i)
      .create('pm_card_visa')

    subscription = user.subscription('main')

    expect(user.subscribed('main')).to be true
    expect(user.subscribed('main', @plan_id)).to be true
    expect(user.subscribed('main', @other_plan_id)).to be false
    expect(subscription.active).to be true
    expect(subscription.cancelled).to be false
    expect(subscription.on_grace_period).to be false
    expect(subscription.recurring).to be true
    expect(subscription.ended).to be false

    # Invoice Tests
    invoice = user.invoices.first
    invoice_period = invoice.invoice_items.first.period

    expect(Time.at(invoice_period.start).strftime('%Y-%m-%d')).to eq(Time.now.strftime('%Y-%m-%d'))
    expect(Time.at(invoice_period.end).strftime('%Y-%m-%d')).to eq(Time.now.at_beginning_of_month.next_month.strftime('%Y-%m-%d'))
  end

  it 'test_creating_subscription_with_trial' do
    user = create_customer('creating_subscription_with_trial')

    # Create Subscription
    user.new_subscription('main', @plan_id)
      .trial_days(7)
      .create('pm_card_visa')

    subscription = user.subscription('main')

    expect(subscription.active).to be true
    expect(subscription.on_trial).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false
    expect(Time.at(subscription.trial_ends_at).strftime('%Y-%m-%d')).to eq((Time.now + 7.days).strftime('%Y-%m-%d'))

    # Cancel Subscription
    subscription.cancel

    expect(subscription.active).to be true
    expect(subscription.on_grace_period).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false

    # Resume Subscription
    subscription.resume

    expect(subscription.active).to be true
    expect(subscription.on_grace_period).to be false
    expect(subscription.on_trial).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false
    expect(Time.at(subscription.trial_ends_at).day).to eq((Time.now + 7.days).day)
  end

  it 'test_creating_subscription_with_explicit_trial' do
    user = create_customer('creating_subscription_with_explicit_trial')

    # Create Subscription
    user.new_subscription('main', @plan_id)
      .trial_until(Time.now + 1.day + 3.hours + 15.minutes)
      .create('pm_card_visa')

    subscription = user.subscription('main')

    expect(subscription.active).to be true
    expect(subscription.on_trial).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false
    expect(Time.at(subscription.trial_ends_at).strftime('%Y-%m-%d')).to eq((Time.now + 1.day + 3.hours + 15.minutes).strftime('%Y-%m-%d'))

    # Cancel Subscription
    subscription.cancel

    expect(subscription.active).to be true
    expect(subscription.on_grace_period).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false

    # Resume Subscription
    subscription.resume

    expect(subscription.active).to be true
    expect(subscription.on_grace_period).to be false
    expect(subscription.on_trial).to be true
    expect(subscription.recurring).to be false
    expect(subscription.ended).to be false
    expect(Time.at(subscription.trial_ends_at).day).to eq((Time.now + 1.day + 3.hours + 15.minutes).day)
  end

  it 'test_subscription_changes_can_be_prorated' do
    user = create_customer('subscription_changes_can_be_prorated')

    subscription = user.new_subscription('main', @premium_plan_id).create('pm_card_visa')

    invoice = user.invoices.first

    expect(invoice.raw_total).to eq(2000)

    subscription.no_prorate.swap(@plan_id)

    # Assert that no new invoice was created because of no prorating.
    expect(user.invoices.first.id).to eq(invoice.id)
    expect(user.upcoming_invoice.raw_total).to eq(1000)

    subscription.swap_and_invoice(@premium_plan_id)

    # Assert that a new invoice was created because of immediate invoicing.
    expect(user.invoices.first.id).not_to eq(invoice.id)
    invoice = user.invoices.first
    expect(invoice.raw_total).to eq(1000)
    expect(user.upcoming_invoice.raw_total).to eq(2000)

    subscription.prorate.swap(@plan_id)

    # Get back from unused time on premium plan on next invoice.
    expect(user.upcoming_invoice.raw_total).to eq(0)
  end

  it 'test_no_prorate_on_subscription_create' do
    user = create_customer('no_prorate_on_subscription_create')

    subscription = user.new_subscription('main', @plan_id)
      .no_prorate
      .create('pm_card_visa', {}, {
        :collection_method => 'send_invoice',
        :days_until_due => 30,
        :backdate_start_date => (Time.now + 5.days - 1.year).beginning_of_day.to_i,
        :billing_cycle_anchor => (Time.now + 5.days).beginning_of_day.to_i,
      })

    expect(subscription.stripe_plan).to eq(@plan_id)
    expect(subscription.active).to be true

    subscription = subscription.swap(@other_plan_id)

    expect(subscription.stripe_plan).to eq(@other_plan_id)
    expect(subscription.active).to be true
  end

  it 'test_swap_and_invoice_after_no_prorate_with_billing_cycle_anchor_delays_invoicing' do
    user = create_customer('always_invoice_after_no_prorate')

    subscription = user.new_subscription('main', @plan_id)
      .no_prorate
      .create('pm_card_visa', {}, {
        :collection_method => 'send_invoice',
        :days_until_due => 30,
        :backdate_start_date => (Time.now + 5.days - 1.year).beginning_of_day.to_i,
        :billing_cycle_anchor => (Time.now + 5.days).beginning_of_day.to_i,
      })

    expect(subscription.stripe_plan).to eq(@plan_id)
    expect(user.invoices.count).to eq(0)
    expect(user.upcoming_invoice.status).to eq('draft')
    expect(subscription.active).to be true

    subscription = subscription.swap_and_invoice(@other_plan_id)

    expect(subscription.stripe_plan).to eq(@other_plan_id)
    expect(user.invoices.count).to eq(0)
    expect(user.upcoming_invoice.status).to eq('draft')
    expect(subscription.active).to be true
  end

  it 'test_trials_can_be_extended' do
    user = create_customer('trials_can_be_extended')

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')

    expect(subscription.trial_ends_at).to be_nil

    trial_ends_at = Time.now + 1.day

    subscription.extend_trial(trial_ends_at)

    expect(subscription.trial_ends_at).to eq(trial_ends_at)
    expect(subscription.as_stripe_subscription.trial_end).to eq(trial_ends_at.to_i)
  end

  it 'test_applying_coupons_to_existing_customers' do
    user = create_customer('applying_coupons_to_existing_customers')

    user.new_subscription('main', @plan_id).create('pm_card_visa')

    user.apply_coupon(@coupon_id)

    customer = user.as_stripe_customer

    expect(customer[:discount][:coupon][:id]).to eq(@coupon_id)
  end

  it 'test_subscription_state_scopes' do
    user = create_customer('subscription_state_scopes')

    # Start with an incomplete subscription.
    subscription = user.subscriptions.create({
      :name => 'yearly',
      :stripe_id => 'xxxx',
      :stripe_status => 'incomplete',
      :stripe_plan => 'stripe-yearly',
      :quantity => 1,
      :trial_ends_at => nil,
      :ends_at => nil,
    })

    # Subscription is incomplete
    expect(user.subscriptions.incomplete.exists?).to be true
    expect(user.subscriptions.active.exists?).to be false
    expect(user.subscriptions.on_trial.exists?).to be false
    expect(user.subscriptions.not_on_trial.exists?).to be true
    expect(user.subscriptions.recurring.exists?).to be true
    expect(user.subscriptions.cancelled.exists?).to be false
    expect(user.subscriptions.not_cancelled.exists?).to be true
    expect(user.subscriptions.on_grace_period.exists?).to be false
    expect(user.subscriptions.not_on_grace_period.exists?).to be true
    expect(user.subscriptions.ended.exists?).to be false

    # Activate.
    subscription.update({:stripe_status => 'active'})

    expect(user.subscriptions.incomplete.exists?).to be false
    expect(user.subscriptions.active.exists?).to be true
    expect(user.subscriptions.on_trial.exists?).to be false
    expect(user.subscriptions.not_on_trial.exists?).to be true
    expect(user.subscriptions.recurring.exists?).to be true
    expect(user.subscriptions.cancelled.exists?).to be false
    expect(user.subscriptions.not_cancelled.exists?).to be true
    expect(user.subscriptions.on_grace_period.exists?).to be false
    expect(user.subscriptions.not_on_grace_period.exists?).to be true
    expect(user.subscriptions.ended.exists?).to be false

    # Put on trial.
    subscription.update({:trial_ends_at => Time.now + 1.day})

    expect(user.subscriptions.incomplete.exists?).to be false
    expect(user.subscriptions.active.exists?).to be true
    expect(user.subscriptions.on_trial.exists?).to be true
    expect(user.subscriptions.not_on_trial.exists?).to be false
    expect(user.subscriptions.recurring.exists?).to be false
    expect(user.subscriptions.cancelled.exists?).to be false
    expect(user.subscriptions.not_cancelled.exists?).to be true
    expect(user.subscriptions.on_grace_period.exists?).to be false
    expect(user.subscriptions.not_on_grace_period.exists?).to be true
    expect(user.subscriptions.ended.exists?).to be false

    # Put on grace period.
    subscription.update({:ends_at => Time.now + 1.day})

    expect(user.subscriptions.incomplete.exists?).to be false
    expect(user.subscriptions.active.exists?).to be true
    expect(user.subscriptions.on_trial.exists?).to be true
    expect(user.subscriptions.not_on_trial.exists?).to be false
    expect(user.subscriptions.recurring.exists?).to be false
    expect(user.subscriptions.cancelled.exists?).to be true
    expect(user.subscriptions.not_cancelled.exists?).to be false
    expect(user.subscriptions.on_grace_period.exists?).to be true
    expect(user.subscriptions.not_on_grace_period.exists?).to be false
    expect(user.subscriptions.ended.exists?).to be false

    # End subscription.
    subscription.update({:ends_at => Time.now - 1.day})

    expect(user.subscriptions.incomplete.exists?).to be false
    expect(user.subscriptions.active.exists?).to be false
    expect(user.subscriptions.on_trial.exists?).to be true
    expect(user.subscriptions.not_on_trial.exists?).to be false
    expect(user.subscriptions.recurring.exists?).to be false
    expect(user.subscriptions.cancelled.exists?).to be true
    expect(user.subscriptions.not_cancelled.exists?).to be false
    expect(user.subscriptions.on_grace_period.exists?).to be false
    expect(user.subscriptions.not_on_grace_period.exists?).to be true
    expect(user.subscriptions.ended.exists?).to be true

    # Enable past_due as active state.
    expect(subscription.active).to be false
    expect(user.subscriptions.active.exists?).to be false

    Reji.keep_past_due_subscriptions_active

    subscription.update({
      :ends_at => nil,
      :stripe_status => 'past_due',
    })

    expect(subscription.active).to be true
    expect(user.subscriptions.active.exists?).to be true

    # Reset deactivate past due state to default to not conflict with other tests.
    Reji.deactivate_past_due = true
  end

  it 'test_retrieve_the_latest_payment_for_a_subscription' do
    user = create_customer('retrieve_the_latest_payment_for_a_subscription')

    begin
      user.new_subscription('main', @plan_id).create('pm_card_threeDSecure2Required')

      raise RSpec::Expectations::ExpectationNotMetError.new('Expected exception PaymentActionRequiredError was not thrown.')
    rescue Reji::PaymentActionRequiredError => exception
      subscription = user.subscription('main')

      payment = subscription.latest_payment

      expect(payment).to be_an_instance_of Reji::Payment
      expect(payment.requires_action).to be true
    end
  end

  it 'test_subscriptions_with_tax_rates_can_be_created' do
    user = create_customer('subscriptions_with_tax_rates_can_be_created')
    user.tax_rates = [@tax_rate_id]

    subscription = user.new_subscription('main', @plan_id).create('pm_card_visa')
    stripe_subscription = subscription.as_stripe_subscription

    expect([stripe_subscription.default_tax_rates.first.id]).to eq([@tax_rate_id])
  end

  it 'test_subscriptions_with_options_can_be_created' do
    user = create_customer('subscriptions_with_options_can_be_created')

    backdate_start_date = (Time.now - 1.month).to_i
    subscription = user.new_subscription('main', @plan_id).create(
      'pm_card_visa', {}, {:backdate_start_date => backdate_start_date}
    )
    stripe_subscription = subscription.as_stripe_subscription

    expect(stripe_subscription.start_date).to eq(backdate_start_date)
  end
end
