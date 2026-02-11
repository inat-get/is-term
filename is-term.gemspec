# frozen_string_literal: true

require_relative 'lib/is-term/info'

Gem::Specification::new do |spec|
  spec.name =      IS::Term::Info::NAME
  spec.version =   IS::Term::Info::VERSION
  spec.summary =   IS::Term::Info::SUMMARY
  spec.authors = [ IS::Term::Info::AUTHOR ]
  spec.license =   IS::Term::Info::LICENSE
  spec.homepage =  IS::Term::Info::HOMEPAGE

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]

  spec.required_ruby_version = '>= 3.4'

  spec.add_dependency 'tty-screen', '~> 0.8'
  spec.add_dependency 'is-boolean', '~> 0.8'

  spec.add_development_dependency 'rdoc'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'yard'
  spec.add_development_dependency 'redcarpet'
  spec.add_development_dependency 'simplecov'
end
