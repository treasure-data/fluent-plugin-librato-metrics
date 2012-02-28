# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "fluent-plugin-librato-metrics"
  s.version     = File.read("VERSION").strip
  s.authors     = ["Sadayuki Furuhashi"]
  s.email       = ["frsyuki@gmail.com"]
  #s.homepage    = "https://github.com/fluent/fluent-plugin-librato-metrics"  # TODO
  s.summary     = %q{Librato metrics output plugin for Fluent event collector}
  s.description = %q{Librato metrics output plugin for Fluent event collector}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
  s.add_dependency "fluentd", "~> 0.10.0"
  s.add_development_dependency "rake", ">= 0.9.2"
end
