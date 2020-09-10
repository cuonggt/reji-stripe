# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
require 'bundler/gem_tasks'

require 'rake'
require 'rspec/core/rake_task'

namespace :dummy do
  require_relative 'spec/dummy/application'
  Dummy::Application.load_tasks
end

desc 'Run specs'
RSpec::Core::RakeTask.new('spec') do |task|
  task.verbose = false
end

require 'rubocop/rake_task'

RuboCop::RakeTask.new do |task|
  task.requires << 'rubocop-rails'
end

desc 'Run the specs and rubocop'
task default: %i[spec rubocop]
