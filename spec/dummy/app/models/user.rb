# frozen_string_literal: true

class User < ActiveRecord::Base
  include Reji::Billable

  def tax_rates
    @tax_rates || []
  end

  def plan_tax_rates
    @plan_tax_rates || {}
  end

  attr_writer :plan_tax_rates

  attr_writer :tax_rates
end
