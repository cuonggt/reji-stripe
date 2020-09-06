# frozen_string_literal: true

Reji.configure do |config|
  # Stripe Keys
  #
  # The Stripe publishable key and secret key give you access to Stripe's
  # API. The "publishable" key is typically used when interacting with
  # Stripe.js while the "secret" key accesses private API endpoints.
  config.key = ENV['STRIPE_KEY']
  config.secret = ENV['STRIPE_SECRET']

  # Stripe Webhooks
  #
  # Your Stripe webhook secret is used to prevent unauthorized requests to
  # your Stripe webhook handling controllers. The tolerance setting will
  # check the drift between the current time and the signed request's.
  config.webhook = {
    :secret => ENV['STRIPE_WEBHOOK_SECRET'],
    :tolerance => ENV['STRIPE_WEBHOOK_TOLERANCE'] || 300,
  }

  # Reji Model
  #
  # This is the model in your application that includes the Billable concern
  # provided by Reji. It will serve as the primary model you use while
  # interacting with Reji related methods, subscriptions, and so on.
  config.model = ENV['REJI_MODEL'] || 'User'
  config.model_id = ENV['REJI_MODEL_ID'] || 'user_id'

  # Currency
  #
  # This is the default currency that will be used when generating charges
  # from your application. Of course, you are welcome to use any of the
  # various world currencies that are currently supported via Stripe.
  config.currency = ENV['REJI_CURRENCY'] || 'usd'
end
