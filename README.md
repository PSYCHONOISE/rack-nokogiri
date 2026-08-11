# Rack::Nokogiri [![CI](https://github.com/PSYCHONOISE/rack-nokogiri/actions/workflows/ci.yml/badge.svg)](https://github.com/PSYCHONOISE/rack-nokogiri/actions/workflows/ci.yml) ![Fork](https://img.shields.io/badge/fork-unindented%2Frack--nokogiri-blue.svg)

Rack Middleware that allows you to manipulate the nodes in your HTML response however you like.


## About this fork

This is a fork of [unindented/rack-nokogiri](https://github.com/unindented/rack-nokogiri),
which its author marked abandoned in December 2015 and which GitHub has since archived.
The upstream repository is read-only: it last saw a commit in June 2017 and cannot accept
issues or pull requests, so there is nowhere to send a fix. This fork exists to carry one.

The original stopped working some time ago, and on more than the version people usually
assume:

* `Rack::Utils.bytesize` was removed in Rack 2, so recomputing `Content-Length` raised
  `NoMethodError` — the gem had been broken on Rack 2 for years, not only on Rack 3.
* `Rack::Utils::HeaderHash` was removed in Rack 3.1, so wrapping the response headers
  raised `NameError` on top of that.
* Concatenating body parts with `+` raised `Encoding::CompatibilityError` on any response
  that arrived as binary with high bytes.
* The original response body was never `close`d when it was replaced, which leaks on Rails.

What this fork changes, and nothing more:

* Rack 1.6 through 3.x, CRuby and JRuby, all covered by one codebase that resolves the
  differences into load-time detector constants rather than pinning a single Rack line.
  See [Compatibility](#compatibility).
* Byte-accurate `Content-Length`, charset-aware body handling, the body closed when
  replaced, and Rack 3 streaming bodies passed through untouched.
* The test suite runs on current Minitest; CI covers every supported Ruby x Rack pair.

The public API is unchanged — `should_process?`, `extract_content` and `process_nodes` all
still exist with their original signatures, so this is a drop-in replacement for the
original. Usage below is the same as it always was.


## Installation

No gem is published from this fork. The `rack-nokogiri` release on RubyGems is upstream's
0.1.0 from August 2013 and contains **none** of the fixes described above, so installing it
by name gets you the broken version. Point your `Gemfile` at the repository instead:

```ruby
gem 'rack-nokogiri', git: 'https://github.com/PSYCHONOISE/rack-nokogiri.git'
```

And then execute:

```sh
$ bundle
```


## Usage

### Adding Rack::Nokogiri to a Rails application

To wrap all `<p>` with class `target` with a `div`, we could do something like this:

```ruby
require 'rack/nokogiri'

class Application < Rails::Application
  config.middleware.use Rack::Nokogiri, css: 'p.target' do |nodes|
    nodes.wrap '<div class="wrapper"></div>'
  end
end
```

If we wanted to use XPath instead of CSS selectors, we could do this instead:

```ruby
require 'rack/nokogiri'

class Application < Rails::Application
  config.middleware.use Rack::Nokogiri, xpath: "//p[@class='target']" do |nodes|
    nodes.wrap '<div class="wrapper"></div>'
  end
end
```

### Adding Rack::Nokogiri to a Sinatra application

For Sinatra we would do:

```ruby
require 'sinatra'
require 'rack/nokogiri'

use Rack::Nokogiri, css: 'p.target' do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end

get('/') do
  '<p class="target">Hello World!</p>'
end
```

### Adding Rack::Nokogiri to a Rackup application

For a Rackup app we would do:

```ruby
require 'rack'
require 'rack/nokogiri'

use Rack::Nokogiri, css: 'p.target' do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end

run lambda { |env|
  [200, {'Content-Type' => 'text/html'}, ['<p class="target">Hello World!</p>']]
}
```


## Compatibility

The middleware detects, at load time, which Rack and Nokogiri generation it is
running against, and adapts:

| Detector | Resolves | Why it varies |
| --- | --- | --- |
| `RACK_3_HEADERS` | `Content-Type` vs `content-type` | Rack 3 mandates lowercase header names; `Rack::Lint` rejects the capitalised form. |
| `HEADERS_CLASS` | `Rack::Headers`, `Rack::Utils::HeaderHash`, or plain `Hash` | `HeaderHash` was removed in Rack 3.1, `Rack::Headers` added in Rack 3.0. |
| `NO_ENTITY_BODY_STATUSES` | lookup hash | `STATUS_WITH_NO_ENTITY_BODY` is a `Set` in Rack 1.x and a `Hash` from Rack 2. |
| `HTML_PARSER` | `Nokogiri::HTML4` or `Nokogiri::HTML` | Nokogiri 1.12 split the HTML4 parser out of the `HTML` shortcut. |
| `JRUBY` | explicit vs sniffed parser encoding | Nokogiri on JRuby is backed by Xerces/NekoHTML, which does not sniff `<meta charset>` as reliably as libxml2. |

Beyond that, responses are handled per the Rack version in play:

* Bodies are buffered as bytes and only then tagged with the charset declared
  in `Content-Type`, so binary and non-UTF-8 responses no longer raise
  `Encoding::CompatibilityError`.
* `Content-Length` is recomputed from the byte length of the re-rendered
  document, in the response's own encoding.
* The original body is `close`d when it is replaced.
* Rack 3 streaming bodies (those responding to `call` rather than `each`) pass
  through untouched, as buffering them would defeat streaming.

### Supported combinations

CI runs the full suite across every cell of Ruby x Rack below:

| | Rack 1.6 | Rack 2.2 | Rack 3.x |
| --- | --- | --- | --- |
| CRuby 3.2 - 4.0 | yes | yes | yes |
| JRuby 9.4 | yes | yes | yes |
| TruffleRuby | yes | yes | yes |

`ruby-head` is also built against Rack 3 as a non-blocking canary.

Run one line locally with the bundled gemfiles:

```sh
$ BUNDLE_GEMFILE=gemfiles/rack1.gemfile bundle exec rake test
$ BUNDLE_GEMFILE=gemfiles/rack2.gemfile bundle exec rake test
$ BUNDLE_GEMFILE=gemfiles/rack3.gemfile bundle exec rake test
```

Rack 1.x is pinned to `rack-test` 1.1 in its gemfile: `rack-test` 2.x reaches
for constants that only exist from Rack 2 onwards and fails on load. That is a
limitation of the test harness, not of the middleware.


## Meta

* Code: `git clone https://github.com/PSYCHONOISE/rack-nokogiri.git`
* Home: <https://github.com/PSYCHONOISE/rack-nokogiri/>
* Upstream (archived): <https://github.com/unindented/rack-nokogiri/>


## Contributors

* Daniel Perez Alvarez ([unindented@gmail.com](mailto:unindented@gmail.com)) — original author
* PSYCHONOISE ([@PSYCHONOISE](https://github.com/PSYCHONOISE)) — fork maintainer

The changes described under [About this fork](#about-this-fork) are the fork
maintainer's; they are not endorsed by the original author, who marked the
project abandoned before any of them were made.


## License

Copyright (c) 2013 Daniel Perez Alvarez ([unindented.org](https://unindented.org/)). This is free software, and may be redistributed under the terms specified in the LICENSE file.

This fork is distributed under those same terms; the original copyright notice is retained
in `LICENSE` unchanged.
