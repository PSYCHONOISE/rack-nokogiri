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
* Responses the block never touched are returned byte for byte, and `HEAD`,
  compressed and fragment responses are no longer corrupted. See the
  [CHANGELOG](CHANGELOG.md) for the full list.
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

### Editing an HTML fragment

Parsing a bare partial as a whole document wraps it in `<html><body>` and a
`DOCTYPE`, which corrupts the responses AJAX and Turbo are made of. Pass
`fragment: true` to parse it as a fragment instead:

```ruby
use Rack::Nokogiri, css: 'p.target', fragment: true do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end
```

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `css:` | — | A CSS selector, or an array of them. |
| `xpath:` | — | An XPath selector, or an array of them. |
| `rules:` | — | Further selector/callable pairs, each editing its own match. |
| `fragment:` | `false` | Parse the body as a fragment rather than a document. |
| `content_type:` | `'text/html'` | String, `Regexp`, or an array of either. |
| `parse_options:` | — | Passed straight to Nokogiri. |
| `max_size:` | — | Skip bodies larger than this many bytes. |
| `html5:` | `false` | Parse with `Nokogiri::HTML5` instead of HTML4. |
| `etag:` | `:recompute` | What to do with an `ETag` once the body changes. |

Selectors accept arrays, and the block is applied to everything they match
between them:

```ruby
use Rack::Nokogiri, css: ['p.target', 'div.target'] do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end
```

For edits that need different treatment per selector, pass `rules:` instead of
a block. Each rule carries its own callable, and one parse serves them all:

```ruby
use Rack::Nokogiri, rules: [
  { css: 'p.target',            with: ->(nodes) { nodes.wrap('<div></div>') } },
  { xpath: "//p[@class='old']", with: ->(nodes) { nodes.remove } }
]
```

`content_type:` widens what is eligible — by default only `text/html` is
touched:

```ruby
use Rack::Nokogiri, css: 'p.target', content_type: %r{application/xhtml\+xml} do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end
```

`max_size:` declines bodies above a byte threshold, checking a declared
`Content-Length` before the body is read at all. Nokogiri builds a DOM several
times the size of its source, so this is the guard against one large response
becoming a memory spike:

```ruby
use Rack::Nokogiri, css: 'p.target', max_size: 2 * 1024 * 1024 do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end
```

### Matching what the browser sees

The HTML4 parser does not apply HTML5 tree construction, so the two disagree on
real documents — HTML4 leaves out the `<tbody>` that every browser inserts:

```
HTML4: <table><tr><td>a</td></tr></table>
HTML5: <table><tbody><tr><td>a</td></tr></tbody></table>
```

A selector written against what you see in devtools therefore misses. Pass
`html5: true` to parse the way the browser does:

```ruby
use Rack::Nokogiri, css: 'tbody tr', html5: true do |nodes|
  nodes.wrap '<div class="wrapper"></div>'
end
```

`Nokogiri::HTML5` is absent on JRuby, where this raises `ArgumentError` as the
middleware is built rather than quietly matching against a different tree. Note
also that the HTML5 parser takes keywords, so `parse_options:` must be a Hash
there rather than a `ParseOptions` bitmask.

### Validators

Rewriting the body changes the representation, and per RFC 9110 a validator
identifies a representation — so an `ETag` copied from the original response
would name bytes nobody receives. Left alone it makes a downstream
`Rack::ConditionalGet` answer `304` to a client holding the *untransformed*
page, and lets caches store the new body under the old validator.

By default the `ETag` is recomputed from the bytes actually sent, keeping the
original's strength (a `W/` prefix survives). Only responses the block actually
edited are touched. `etag:` takes:

| Value | Effect |
| --- | --- |
| `:recompute` | Default. Replace with a digest of the body being sent. |
| `:weak` | Same, but always weak. |
| `:delete` | Drop the header and let something downstream set one. |
| `:preserve` | Leave it stale, for callers who know better. |

`Last-Modified` is left alone: the transformation is deterministic, so it stays
consistent with the resource's modification time.

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

### When the middleware stays out of the way

A response is passed through untouched, rather than parsed and re-serialised,
when any of the following holds. This matters because round-tripping through
Nokogiri normalises the markup, so processing a response is never free of
side effects:

* the selector matched nothing, so the block never ran;
* the request was a `HEAD`, whose response carries headers but no body;
* the response carries a `Content-Encoding` — a gzipped body is not HTML;
* the response carries a `Transfer-Encoding`;
* the status admits no entity body;
* the body is a Rack 3 streaming body, which buffering would defeat;
* the `Content-Type` does not match `content_type:`, which defaults to `text/html`;
* the body is larger than `max_size:`;
* no block and no `rules:` were given.

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
