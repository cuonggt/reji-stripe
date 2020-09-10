# frozen_string_literal: true

module Reji
  module Prorates
    extend ActiveSupport::Concern

    # Indicate that the plan change should not be prorated.
    def no_prorate
      @proration_behavior = 'none'

      self
    end

    # Indicate that the plan change should be prorated.
    def prorate
      @proration_behavior = 'create_prorations'

      self
    end

    # Indicate that the plan change should always be invoiced.
    def always_invoice
      @proration_behavior = 'always_invoice'
    end

    # Set the prorating behavior.
    def set_proration_behavior(value)
      @proration_behavior = value

      self
    end

    # Determine the prorating behavior when updating the subscription.
    def proration_behavior
      @proration_behavior ||= 'create_prorations'
    end
  end
end
