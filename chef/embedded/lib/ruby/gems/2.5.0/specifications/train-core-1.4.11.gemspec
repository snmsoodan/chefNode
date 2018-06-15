# -*- encoding: utf-8 -*-
# stub: train-core 1.4.11 ruby lib

Gem::Specification.new do |s|
  s.name = "train-core".freeze
  s.version = "1.4.11"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Dominik Richter".freeze]
  s.date = "2018-05-17"
  s.description = "A minimal Train with a selected set of backends, ssh, winrm, and docker.".freeze
  s.email = ["dominik.richter@gmail.com".freeze]
  s.homepage = "https://github.com/chef/train/".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.rubygems_version = "2.7.6".freeze
  s.summary = "Transport interface to talk to a selected set of backends.".freeze

  s.installed_by_version = "2.7.6" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<mixlib-shellout>.freeze, ["~> 2.0"])
      s.add_runtime_dependency(%q<json>.freeze, ["< 3.0", ">= 1.8"])
    else
      s.add_dependency(%q<mixlib-shellout>.freeze, ["~> 2.0"])
      s.add_dependency(%q<json>.freeze, ["< 3.0", ">= 1.8"])
    end
  else
    s.add_dependency(%q<mixlib-shellout>.freeze, ["~> 2.0"])
    s.add_dependency(%q<json>.freeze, ["< 3.0", ">= 1.8"])
  end
end
