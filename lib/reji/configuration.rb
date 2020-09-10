# frozen_string_literal: true

module Reji
  class Configuration
    # Stripe Keys
    #
    # The Stripe publishable key and secret key give you access to Stripe's
    # API. The "publishable" key is typically used when interacting with
    # Stripe.js while the "secret" key accesses private API endpoints.
    attr_accessor :key
    attr_accessor :secret

    # Stripe Webhooks
    #
    # Your Stripe webhook secret is used to prevent unauthorized requests to
    # your Stripe webhook handling controllers. The tolerance setting will
    # check the drift between the current time and the signed request's.
    attr_accessor :webhook

    # Reji Model
    #
    # This is the model in your application that includes the Billable concern
    # provided by Reji. It will serve as the primary model you use while
    # interacting with Reji related methods, subscriptions, and so on.
    attr_accessor :model
    attr_accessor :model_id

    # Currency
    #
    # This is the default currency that will be used when generating charges
    # from your application. Of course, you are welcome to use any of the
    # various world currencies that are currently supported via Stripe.
    attr_accessor :currency

    def initialize
      @key = ENV['STRIPE_KEY']
      @secret = ENV['STRIPE_SECRET']
      @webhook = {
        secret: ENV['STRIPE_WEBHOOK_SECRET'],
        tolerance: ENV['STRIPE_WEBHOOK_TOLERANCE'] || 300,
      }
      @model = ENV['REJI_MODEL'] || 'User'
      @model_id = ENV['REJI_MODEL_ID'] || 'user_id'
      @currency = ENV['REJI_CURRENCY'] || 'usd'
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configuration=(config)
    @configuration = config
  end

  def self.configure
    yield(configuration)
  end
end
