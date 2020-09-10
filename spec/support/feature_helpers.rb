# frozen_string_literal: true

require 'reji'

Reji.configure do |config|
  config.secret = ENV['STRIPE_SECRET']
end

Stripe.api_key = ENV['STRIPE_SECRET']

module Reji
  module Test
    module FeatureHelpers
      def stripe_prefix
        'cashier-test-'
      end

      sleep(2)

      protected def delete_stripe_resource(resource)
        resource.delete
      rescue Stripe::InvalidRequestError => _e
        #
      end

      protected def create_customer(description = 'cuong', options = {})
        User.create({
          email: "#{description}@reji-test.com",
        }.merge(options))
      end
    end
  end
end
