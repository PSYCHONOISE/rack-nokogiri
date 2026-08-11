# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'rack/nokogiri/version'

Gem::Specification.new do |gem|
  gem.name          = 'rack-nokogiri'
  gem.version       = Rack::Nokogiri::VERSION
  # Original author first, fork maintainer second; the arrays are positional.
  gem.authors       = ['Daniel Perez Alvarez', 'PSYCHONOISE']
  gem.email         = ['unindented@gmail.com',
                       '9990726+PSYCHONOISE@users.noreply.github.com']
  gem.description   = %q{Rack Middleware for node manipulation.}
  gem.summary       = %q{Rack Middleware that allows you to manipulate the nodes in your response however you like.}
  # Fork of the archived unindented/rack-nokogiri; see the README for why.
  gem.homepage      = 'https://github.com/PSYCHONOISE/rack-nokogiri'
  gem.license       = 'MIT'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  # 2.3 is the floor for `String#b` and keyword-argument forwarding used by
  # the encoding handling; JRuby 9.2+ reports a compatible RUBY_VERSION.
  gem.required_ruby_version = '>= 2.3.0'

  # `source_code_uri` is left out on purpose: RubyGems warns when it repeats
  # `homepage_uri`, and shows only the first of the two anyway.
  gem.metadata = {
    'homepage_uri'    => gem.homepage,
    'bug_tracker_uri' => "#{gem.homepage}/issues",
    'changelog_uri'   => "#{gem.homepage}/blob/master/CHANGELOG.md"
  }

  # Rack 1.x through 3.x are supported; the middleware detects the header
  # conventions and body protocol of whichever one is loaded.
  gem.add_runtime_dependency 'rack',     '>= 1.0.0'
  gem.add_runtime_dependency 'nokogiri', '>= 1.4.0'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'minitest'
  gem.add_development_dependency 'rack-test'
end
