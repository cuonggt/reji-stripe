# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'reji/version'

Gem::Specification.new do |s|
  s.name = 'reji'
  s.version = Reji::VERSION
  s.author = ['Cuong Giang']
  s.email = ['thaicuong.giang@gmail.com']
  s.homepage = 'https://github.com/cuonggt/reji'
  s.summary = "Reji provides an expressive, fluent interface to Stripe's subscription billing services."
  s.description = "Reji provides an expressive, fluent interface to Stripe's subscription billing services."
  s.license = 'MIT'

  s.required_ruby_version = Gem::Requirement.new('>= 2.4.0')

  s.files = `git ls-files`.split("\n")
  s.require_paths = ['lib']
  s.test_files = `git ls-files -- {spec}/*`.split("\n")

  s.add_dependency 'actionmailer', '>= 5.0'
  s.add_dependency 'activerecord', '>= 5.0'
  s.add_dependency 'money', '>= 6.0'
  s.add_dependency 'railties', '>= 5.0'
  s.add_dependency 'stripe', '>= 5.0'
  s.add_dependency 'wicked_pdf'
  s.add_dependency 'wkhtmltopdf-binary'
  s.add_development_dependency 'appraisal'
  s.add_development_dependency 'rspec-rails', '~> 4.0.1'
  s.add_development_dependency 'sqlite3', '~> 1.4.2'
end
