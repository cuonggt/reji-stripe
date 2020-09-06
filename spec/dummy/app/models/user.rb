# frozen_string_literal: true

class User < ActiveRecord::Base
  include Reji::Billable

  def tax_rates
    @tax_rates || {}
  end

  def plan_tax_rates
    @plan_tax_rates || {}
  end

  def plan_tax_rates=(value)
    @plan_tax_rates = value
  end

  def tax_rates=(value)
    @tax_rates = value
  end
end
