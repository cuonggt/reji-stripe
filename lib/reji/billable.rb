# frozen_string_literal: true

module Reji
  module Billable
    extend ActiveSupport::Concern

    include Reji::ManagesCustomer
    include Reji::ManagesInvoices
    include Reji::ManagesPaymentMethods
    include Reji::ManagesSubscriptions
    include Reji::PerformsCharges
  end
end
