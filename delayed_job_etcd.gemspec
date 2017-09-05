# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'delayed_job_etcd/version'

Gem::Specification.new do |spec|
  spec.name          = "delayed_job_etcd"
  spec.version       = DelayedJobEtcd::VERSION
  spec.authors       = ["Jonathan Calvert"]
  spec.email         = ["athemeus@athemeus.com"]

  spec.summary       = %q{Delayed Job backend for etcd}
  spec.description   = %q{Delayed Job backend for etcd}
  spec.homepage      = "http://github.com/somevalidrepo"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_runtime_dependency     'delayed_job',  '~> 4.1.2'
  spec.add_runtime_dependency     'etcdv3', '~> 0.6.0'
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "activerecord"
  spec.add_development_dependency "sqlite3"
end
