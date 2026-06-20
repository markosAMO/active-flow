# frozen_string_literal: true

require_relative "lib/active_flow/version"

Gem::Specification.new do |spec|
  spec.name    = "active_flow"
  spec.version = ActiveFlow::VERSION
  spec.authors = ["mgonidev"]
  spec.email   = ["matiasgoni@live.com"]

  spec.summary     = "Serialize ActiveRecord models as React Flow nodes and edges"
  spec.description = "DSL to mark AR models as flowable, generating React Flow compatible JSON from instances and their associations"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1.0"


  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 7.1.0"

  spec.add_development_dependency "rails",   "~> 7.1.0"
  spec.add_development_dependency "rspec",   "~> 3.0"
  spec.add_development_dependency "sqlite3", "~> 1.4"
end
