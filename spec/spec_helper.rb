# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'rails/all'
require 'dummy/application'

require 'rspec/rails'

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

Dummy::Application.initialize!

ActiveRecord::Migration.maintain_test_schema!

ActiveRecord::Schema.verbose = false
load 'dummy/db/schema.rb'

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.infer_spec_type_from_file_location!

  %i[request].each do |type|
    config.include(Reji::Test::FeatureHelpers, type: type)
  end
end
