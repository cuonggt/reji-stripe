# frozen_string_literal: true

module Reji
  class WebhookController < ActionController::Base
    before_action :verify_webhook_signature

    def handle_webhook
      payload = JSON.parse(request.body.read)

      type = payload['type']

      return missing_method if type.nil?

      method = "handle_#{payload['type'].tr('.', '_')}"

      respond_to?(method, true) ? send(method, payload) : missing_method
    end

    # Handle customer subscription updated.
    # rubocop:disable Metrics/MethodLength
    protected def handle_customer_subscription_updated(payload)
      user = get_user_by_stripe_id(payload.dig('data', 'object', 'customer'))

      return success_method if user.nil?

      data = payload.dig('data', 'object')

      return success_method if data.nil?

      user.subscriptions
        .select { |subscription| subscription.stripe_id == data['id'] }
        .each do |subscription|
          if data['status'] == 'incomplete_expired'
            subscription.items.destroy_all
            subscription.destroy

            return success_method
          end

          # Plan...
          subscription.stripe_plan = data.dig('plan', 'id')

          # Quantity...
          subscription.quantity = data['quantity']

          # Trial ending date...
          if data['trial_end'].present?
            if subscription.trial_ends_at.nil? || subscription.trial_ends_at.to_i != data['trial_end']
              subscription.trial_ends_at = Time.zone.at(data['trial_end'])
            end
          end

          # Cancellation date...
          subscription.ends_at =
            if data['cancel_at_period_end'].blank?
              nil
            else
              (subscription.on_trial ? subscription.trial_ends_at : Time.zone.at(data['cancel_at_period_end']))
            end

          # Status...
          subscription.stripe_status = data['status'] unless data['status'].nil?

          subscription.save

          # Update subscription items...
          next unless data.key?('items')

          plans = []

          items = data.dig('items', 'data') || []

          items.each do |item|
            plans << item.dig('plan', 'id')

            subscription.items.find_or_create_by({ stripe_id: item['id'] }) do |subscription_item|
              subscription_item.stripe_plan = item.dig('plan', 'id')
              subscription_item.quantity = item['quantity']
            end
          end

          # Delete items that aren't attached to the subscription anymore...
          subscription.items.where('stripe_plan NOT IN (?)', plans).destroy_all
        end

      success_method
    end
    # rubocop:enable Metrics/MethodLength

    # Handle a cancelled customer from a Stripe subscription.
    protected def handle_customer_subscription_deleted(payload)
      user = get_user_by_stripe_id(payload.dig('data', 'object', 'customer'))

      unless user.nil?
        user.subscriptions
          .select { |subscription| subscription.stripe_id == payload.dig('data', 'object', 'id') }
          .each(&:mark_as_cancelled)
      end

      success_method
    end

    # Handle customer updated.
    protected def handle_customer_updated(payload)
      user = get_user_by_stripe_id(payload.dig('data', 'object', 'id'))

      user&.update_default_payment_method_from_stripe

      success_method
    end

    # Handle deleted customer.
    protected def handle_customer_deleted(payload)
      user = get_user_by_stripe_id(payload.dig('data', 'object', 'id'))

      unless user.nil?
        user.subscriptions.each { |subscription| subscription.skip_trial.mark_as_cancelled }

        user.update({
          stripe_id: nil,
          trial_ends_at: nil,
          card_brand: nil,
          card_last_four: nil,
        })
      end

      success_method
    end

    # Get the billable entity instance by Stripe ID.
    protected def get_user_by_stripe_id(stripe_id)
      Reji.find_billable(stripe_id)
    end

    # Handle successful calls on the controller.
    protected def success_method
      render plain: 'Webhook Handled', status: :ok
    end

    # Handle calls to missing methods on the controller.
    protected def missing_method
      head :ok
    end

    protected def verify_webhook_signature
      return if Reji.configuration.webhook[:secret].blank?

      begin
        Stripe::Webhook.construct_event(
          request.body.read,
          request.env['HTTP_STRIPE_SIGNATURE'],
          Reji.configuration.webhook[:secret]
        )
      rescue Stripe::SignatureVerificationError => e
        raise AccessDeniedHttpError, e.message
      end
    end
  end
end
