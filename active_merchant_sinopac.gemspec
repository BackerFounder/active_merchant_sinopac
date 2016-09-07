# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "active_merchant_sinopac/version"

Gem::Specification.new do |spec|
  spec.name          = "active_merchant_sinopac"
  spec.version       = ActiveMerchantSinopac::VERSION
  spec.authors       = ["BackerFounder"]
  spec.email         = ["hello@backer-founder.com"]

  spec.summary       = "SinoPac Active Merchant Integration"
  spec.homepage      = "https://github.com/BackerFounder/active_merchant_sinopac"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
end
