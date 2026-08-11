# frozen_string_literal: true

require 'minitest/autorun'
require 'rack/test'
require 'nokogiri'
require 'stringio'
require 'zlib'
require 'digest'

begin
  require 'minitest/reporters'
  Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)
rescue LoadError
  # Optional pretty output; the default reporter is fine.
end

require File.expand_path('../support/expectations', __FILE__)
require File.expand_path('../../lib/rack/nokogiri', __FILE__)

include Rack::Test::Methods

# Rack 3 requires lowercase header names, Rack 1/2 conventionally capitalise
# them. Specs declare headers in the shape the host Rack expects.
def header_name(name)
  Rack::Nokogiri::RACK_3_HEADERS ? name.downcase : name
end

def normalize_headers(headers)
  headers.each_with_object({}) { |(key, value), memo| memo[key.to_s.downcase] = value }
end

# Every response built through this helper goes through Rack::Lint, so a
# protocol violation fails the spec that provoked it rather than waiting for
# an assertion written to look for it.
def create_app(status, headers, content, options, &block)
  Rack::Lint.new(create_raw_app(status, headers, content, options, &block))
end

# Unlinted, for the handful of specs that deliberately feed the middleware a
# response Rack itself considers malformed. Linting those would only assert
# that the fixture is invalid, which is the point of the fixture.
def create_raw_app(status, headers, content, options, &block)
  app = lambda { |_env| [status, headers, [content]] }
  Rack::Nokogiri.new(app, options, &block)
end
