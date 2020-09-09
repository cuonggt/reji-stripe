# frozen_string_literal: true

module Reji
  class WebhookController < ActionController::Base
    before_action :verify_webhook_signature

    def handle_webhook
      payload = JSON.parse(request.body.read)

      type = payload['type']

      return self.missing_method if type.nil?

      method = "handle_#{payload['type'].gsub('.', '_')}"

      self.respond_to?(method, true) ?
        self.send(method, payload) :
        self.missing_method
    end

    protected

    # Handle customer subscription updated.
    def handle_customer_subscription_updated(payload)
      user = self.get_user_by_stripe_id(payload.dig('data', 'object', 'customer'))

      return self.success_method if user.nil?

      data = payload.dig('data', 'object')

      return self.success_method if data.nil?

      user.subscriptions
        .select { |subscription| subscription.stripe_id == data['id'] }
        .each do |subscription|
          if data['status'] == 'incomplete_expired'
            subscription.items.destroy_all
            subscription.destroy

            return self.success_method
          end

          # Plan...
          subscription.stripe_plan = data.dig('plan', 'id')

          # Quantity...
          subscription.quantity = data['quantity']

          # Trial ending date...
          unless data['trial_end'].nil?
            if subscription.trial_ends_at.nil? || subscription.trial_ends_at.to_i != data['trial_end']
              subscription.trial_ends_at = Time.at(data['trial_end'])
            end
          end

          # Cancellation date...
          unless data['cancel_at_period_end'].nil?
            if data['cancel_at_period_end']
              subscription.ends_at = subscription.on_trial ?
                subscription.trial_ends_at :
                Time.at(data['cancel_at_period_end'])
            else
              subscription.ends_at = nil
            end
          end

          # Status...
          unless data['status'].nil?
            subscription.stripe_status = data['status']
          end

          subscription.save

          # Update subscription items...
          if data.key?('items')
            plans = []

            items = data.dig('items', 'data')

            unless items.blank?
              items.each do |item|
                plans << item.dig('plan', 'id')

                subscription_item = subscription.items.find_or_create_by({:stripe_id => item['id']}) do |subscription_item|
                  subscription_item.stripe_plan = item.dig('plan', 'id')
                  subscription_item.quantity = item['quantity']
                end
              end
            end

            # Delete items that aren't attached to the subscription anymore...
            subscription.items.where('stripe_plan NOT IN (?)', plans).destroy_all
          end
        end

      self.success_method
    end

    # Handle a cancelled customer from a Stripe subscription.
    def handle_customer_subscription_deleted(payload)
      user = self.get_user_by_stripe_id(payload.dig('data', 'object', 'customer'))

      unless user.nil?
        user.subscriptions
          .select { |subscription| subscription.stripe_id == payload.dig('data', 'object', 'id') }
          .each { |subscription| subscription.mark_as_cancelled }
      end

      self.success_method
    end

    # Handle customer updated.
    def handle_customer_updated(payload)
      user = self.get_user_by_stripe_id(payload.dig('data', 'object', 'id'))

      user.update_default_payment_method_from_stripe unless user.nil?

      self.success_method
    end

    # Handle deleted customer.
    def handle_customer_deleted(payload)
      user = self.get_user_by_stripe_id(payload.dig('data', 'object', 'id'))

      unless user.nil?
        user.subscriptions.each { |subscription| subscription.skip_trial.mark_as_cancelled }

        user.update({
          :stripe_id => nil,
          :trial_ends_at => nil,
          :card_brand => nil,
          :card_last_four => nil,
        })
      end

      self.success_method
    end

    # Get the billable entity instance by Stripe ID.
    def get_user_by_stripe_id(stripe_id)
      Reji.find_billable(stripe_id)
    end

    # Handle successful calls on the controller.
    def success_method
      render plain: 'Webhook Handled', status: 200
    end

    # Handle calls to missing methods on the controller.
    def missing_method
      head :ok
    end

    private

    def verify_webhook_signature
      return if Reji.configuration.webhook[:secret].blank?

      begin
        Stripe::Webhook.construct_event(
          request.body.read,
          request.env['HTTP_STRIPE_SIGNATURE'],
          Reji.configuration.webhook[:secret],
        )
      rescue Stripe::SignatureVerificationError => e
        raise AccessDeniedHttpError.new(e.message)
      end
    end
  end
end
