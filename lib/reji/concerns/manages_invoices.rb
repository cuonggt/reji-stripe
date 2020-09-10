# frozen_string_literal: true

module Reji
  module ManagesInvoices
    extend ActiveSupport::Concern

    # Add an invoice item to the customer's upcoming invoice.
    def tab(description, amount, options = {})
      assert_customer_exists

      options = {
        customer: stripe_id,
        amount: amount,
        currency: preferred_currency,
        description: description,
      }.merge(options)

      Stripe::InvoiceItem.create(options, stripe_options)
    end

    # Invoice the customer for the given amount and generate an invoice immediately.
    def invoice_for(description, amount, tab_options = {}, invoice_options = {})
      tab(description, amount, tab_options)

      invoice(invoice_options)
    end

    # Invoice the billable entity outside of the regular billing cycle.
    def invoice(options = {})
      assert_customer_exists

      begin
        stripe_invoice = Stripe::Invoice.create(options.merge({ customer: stripe_id }), stripe_options)

        stripe_invoice =
          if stripe_invoice.collection_method == 'charge_automatically'
            stripe_invoice.pay
          else
            stripe_invoice.send_invoice
          end

        Invoice.new(self, stripe_invoice)
      rescue Stripe::InvalidRequestError => _e
        false
      rescue Stripe::CardError => _e
        Payment.new(
          Stripe::PaymentIntent.retrieve(
            { id: stripe_invoice.payment_intent, expand: ['invoice.subscription'] },
            stripe_options
          )
        ).validate
      end
    end

    # Get the entity's upcoming invoice.
    def upcoming_invoice
      return unless stripe_id?

      begin
        stripe_invoice = Stripe::Invoice.upcoming({ customer: stripe_id }, stripe_options)

        Invoice.new(self, stripe_invoice)
      rescue Stripe::InvalidRequestError => _e
        #
      end
    end

    # Find an invoice by ID.
    def find_invoice(id)
      stripe_invoice = nil

      begin
        stripe_invoice = Stripe::Invoice.retrieve(id, stripe_options)
      rescue StandardError => _e
        #
      end

      stripe_invoice ? Invoice.new(self, stripe_invoice) : nil
    end

    # Find an invoice or throw a 404 or 403 error.
    def find_invoice_or_fail(id)
      begin
        invoice = find_invoice(id)
      rescue InvalidInvoiceError => e
        raise Reji::AccessDeniedHttpError, e.message
      end

      raise ActiveRecord::RecordNotFound if invoice.nil?

      invoice
    end

    # Create an invoice download response.
    def download_invoice(id, data, filename = nil)
      invoice = find_invoice_or_fail(id)

      filename ? invoice.download_as(filename, data) : invoice.download(data)
    end

    # Get a collection of the entity's invoices.
    def invoices(include_pending = false, parameters = {})
      return [] unless stripe_id?

      invoices = []

      parameters = { limit: 24 }.merge(parameters)

      stripe_invoices = Stripe::Invoice.list(
        { customer: stripe_id }.merge(parameters),
        stripe_options
      )

      # Here we will loop through the Stripe invoices and create our own custom Invoice
      # instances that have more helper methods and are generally more convenient to
      # work with than the plain Stripe objects are. Then, we'll return the array.
      stripe_invoices&.data&.each do |invoice|
        invoices << Invoice.new(self, invoice) if invoice.paid || include_pending
      end

      invoices
    end

    # Get an array of the entity's invoices.
    def invoices_include_pending(parameters = {})
      invoices(true, parameters)
    end
  end
end
