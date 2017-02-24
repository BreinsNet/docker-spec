# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'docker/spec/version'

Gem::Specification.new do |spec|
  spec.name          = "docker-spec"
  spec.version       = Docker::Spec::VERSION
  spec.authors       = ["Juan Breinlinger"]
  spec.email         = ["<juan.brein@breins.net>"]

  spec.summary       = %q{A docker spec library to build and test docker containers}
  spec.description   = %q{A docker spec library to build and test docker containers}
  spec.homepage      = "https://github.com/BreinsNet/docker-spec"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_dependency 'serverspec'
  spec.add_dependency 'docker-api'
  spec.add_dependency 'pry'
  spec.add_dependency 'highline'
  spec.add_dependency 'popen4'
  spec.add_dependency 'colorize'
  spec.add_dependency 'logger'
  spec.add_dependency 'moneta'
end
