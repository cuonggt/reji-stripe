# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table 'subscription_items', force: true do |t|
    t.bigint 'subscription_id', null: false
    t.string 'stripe_id', null: false
    t.string 'stripe_plan', null: false
    t.integer 'quantity', null: false
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
    t.index ['stripe_id'], name: 'index_subscription_items_on_stripe_id'
    t.index %w[subscription_id stripe_plan], name: 'index_subscription_items_on_subscription_id_and_stripe_plan', unique: true
  end

  create_table 'subscriptions', force: true do |t|
    t.bigint 'user_id', null: false
    t.string 'name', null: false
    t.string 'stripe_id', null: false
    t.string 'stripe_status', null: false
    t.string 'stripe_plan'
    t.integer 'quantity'
    t.timestamp 'trial_ends_at'
    t.timestamp 'ends_at'
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
    t.index %w[user_id stripe_status], name: 'index_subscriptions_on_user_id_and_stripe_status'
  end

  create_table 'users', force: true do |t|
    t.string 'email', default: '', null: false
    t.string 'stripe_id'
    t.string 'card_brand'
    t.string 'card_last_four', limit: 4
    t.timestamp 'trial_ends_at'
    t.datetime 'created_at', precision: 6, null: false
    t.datetime 'updated_at', precision: 6, null: false
    t.index ['email'], name: 'index_users_on_email', unique: true
  end
end
