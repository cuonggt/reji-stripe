# frozen_string_literal: true

require 'rails/generators/base'
require 'rails/generators/active_record'

module Reji
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root(File.expand_path('templates', __dir__))

      def create_reji_initializer
        copy_file('reji.rb', 'config/initializers/reji.rb')
      end

      def create_reji_migration
        copy_migration('add_reji_to_users')
        copy_migration('create_subscriptions')
        copy_migration('create_subscription_items')
      end

      # for generating a timestamp when using `create_migration`
      def self.next_migration_number(dir)
        ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      private def copy_migration(migration_name, config = {})
        return if migration_exists?(migration_name)

        migration_template(
          "db/migrate/#{migration_name}.rb.erb",
          "db/migrate/#{migration_name}.rb",
          config.merge(migration_version: migration_version)
        )
      end

      private def migration_exists?(name)
        existing_migrations.include?(name)
      end

      private def existing_migrations
        @existing_migrations ||= Dir.glob('db/migrate/*.rb').map do |file|
          migration_name_without_timestamp(file)
        end
      end

      private def migration_name_without_timestamp(file)
        file.sub(%r{^.*(db/migrate/)(?:\d+_)?}, '')
      end

      private def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end

      private def migration_primary_key_type_string
        ", id: :#{configured_key_type}" if configured_key_type
      end

      private def configured_key_type
        Rails.configuration.generators.active_record[:primary_key_type]
      end
    end
  end
end
