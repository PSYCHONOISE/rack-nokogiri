# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-11

First release of the fork of [unindented/rack-nokogiri](https://github.com/unindented/rack-nokogiri),
which was marked abandoned in 2015 and has since been archived. Version 0.1.0 on
RubyGems is upstream's August 2013 release and contains none of the following.

### Fixed

- `Content-Length` is recomputed with `String#bytesize`. `Rack::Utils.bytesize`
  was removed in Rack 2, so the middleware raised `NoMethodError` on every
  processed response — it had been broken on Rack 2 for years, not only on Rack 3.
- Response headers are wrapped in whichever class the host Rack provides.
  `Rack::Utils::HeaderHash` was removed in Rack 3.1 and raised `NameError`.
- Body parts are buffered as bytes and only then tagged with the charset declared
  in `Content-Type`. Concatenating them with `+` raised
  `Encoding::CompatibilityError` on any binary body carrying high bytes.
- The original response body is closed when it is replaced. It previously leaked,
  which matters under Rails.
- A response whose selector matched nothing is returned byte for byte. It was
  re-serialised regardless, and Nokogiri normalises what it round-trips, so an
  untouched response came back with an injected `DOCTYPE`.
- `HEAD` requests no longer gain a body. The empty body was parsed and serialised
  back into roughly 100 bytes of `DOCTYPE`, with a matching `Content-Length`.
- Responses carrying a `Content-Encoding` are passed through. A gzipped body was
  parsed as HTML and re-serialised, destroying the response.
- Rack 3 streaming bodies — those responding to `call` rather than `each` — are
  passed through instead of being buffered.
- An `ETag` is recomputed once the body has been rewritten. It was carried over
  unchanged, so it named a representation that was never sent: a downstream
  `Rack::ConditionalGet` would answer `304` to a client holding the
  untransformed page, and caches would store the new body under the old
  validator. Only edited responses are affected, and the original's strength is
  kept. Configurable through `etag:`.

### Added

- `fragment: true`, which parses the body with `Nokogiri::HTML.fragment`. Parsing
  a bare partial as a document wrapped it in `<html><body>` and a `DOCTYPE`,
  corrupting the responses that AJAX and Turbo are made of.
- Support for Rack 1.6 through 3.x, and for JRuby, from a single codebase. The
  differences are resolved once at load time into detector constants
  (`RACK_3_HEADERS`, `HEADERS_CLASS`, `NO_ENTITY_BODY_STATUSES`, `HTML_PARSER`,
  `JRUBY`) rather than by pinning a version.
- `css:` and `xpath:` accept an array of selectors as well as a single one.
- `rules:`, taking selector/callable pairs, so several independent edits can
  share one parse instead of one block receiving their merged `NodeSet`.
- `content_type:`, a String, `Regexp`, or array of either, replacing the
  hardcoded `text/html` test.
- `parse_options:`, handed straight to Nokogiri.
- `html5:`, parsing with `Nokogiri::HTML5` so selectors match the tree a browser
  builds — HTML4 omits the `<tbody>` that HTML5 inserts, among much else. The
  parser is absent on JRuby, where this raises `ArgumentError` as the middleware
  is built rather than silently matching a different tree.
- `etag:`, choosing between `:recompute`, `:weak`, `:delete` and `:preserve`.
- `max_size:`, which declines bodies above a byte threshold. A declared
  `Content-Length` is checked before the body is read at all. Nokogiri builds a
  DOM several times the size of its source, so an unbounded body was an
  unbounded allocation.
- A CI matrix over every supported Ruby x Rack pair. The whole suite now runs
  through `Rack::Lint`, which catches protocol violations as they happen rather
  than waiting for an assertion written to look for them.

### Changed

- `process_nodes` returns whether any rule's callable was invoked, which is what
  tells the middleware if the document is worth re-serialising. It previously
  returned the block's own return value.
- `should_process?` takes two further optional arguments, the response body and
  the Rack env, used to detect streaming bodies and `HEAD` requests. Existing
  two-argument calls still work.
- `required_ruby_version` is now `>= 2.3.0`.

### Removed

- The Travis configuration, which tested Ruby 1.9 through 2.1.

[0.2.0]: https://github.com/PSYCHONOISE/rack-nokogiri/releases/tag/v0.2.0
