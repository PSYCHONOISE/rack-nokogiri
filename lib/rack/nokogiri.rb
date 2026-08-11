# frozen_string_literal: true

require 'rack/nokogiri/version'

require 'rack'
require 'nokogiri'

module Rack
  class Nokogiri

    # ----------------------------------------------------------------------
    # Detectors
    #
    # Everything that differs between Rack 1.x/2.x/3.x, between CRuby and
    # JRuby, or between Nokogiri generations is resolved once, at load time,
    # into a constant. The request path below branches on those constants
    # only, so behaviour is identical across every supported combination.
    # ----------------------------------------------------------------------

    # `Rack.release` predates `Rack::VERSION` being a string, and very old
    # releases expose neither in a usable shape.
    RACK_RELEASE = if Rack.respond_to?(:release)
                     Rack.release.to_s
                   elsif Rack.const_defined?(:VERSION)
                     Array(Rack::VERSION).join('.')
                   else
                     '1.0.0'
                   end

    RACK_MAJOR = RACK_RELEASE.split('.').first.to_i

    # Rack 3 made lowercase header names mandatory; Rack 1/2 conventionally
    # use the capitalised form. Both are legal HTTP, but `Rack::Lint` is
    # strict about it, so we emit whatever the host Rack expects.
    RACK_3_HEADERS = RACK_MAJOR >= 3

    CONTENT_TYPE      = RACK_3_HEADERS ? 'content-type'      : 'Content-Type'
    CONTENT_LENGTH    = RACK_3_HEADERS ? 'content-length'    : 'Content-Length'
    TRANSFER_ENCODING = RACK_3_HEADERS ? 'transfer-encoding' : 'Transfer-Encoding'

    # The case-preserving hash to hand back downstream:
    #   * `Rack::Headers`           — Rack >= 3.0
    #   * `Rack::Utils::HeaderHash` — Rack 1.x .. 3.0 (removed in 3.1)
    #   * plain `Hash`              — anything else
    HEADERS_CLASS = if Rack.const_defined?(:Headers)
                      Rack::Headers
                    elsif Rack::Utils.const_defined?(:HeaderHash)
                      Rack::Utils::HeaderHash
                    end

    # `STATUS_WITH_NO_ENTITY_BODY` is an Array in Rack 1.x and a Hash from
    # Rack 2 onwards. Normalised to a lookup hash either way.
    NO_ENTITY_BODY_STATUSES = begin
      statuses = if Rack::Utils.const_defined?(:STATUS_WITH_NO_ENTITY_BODY)
                   raw = Rack::Utils::STATUS_WITH_NO_ENTITY_BODY
                   raw.respond_to?(:keys) ? raw.keys : raw.to_a
                 else
                   (100..199).to_a + [204, 304]
                 end
      statuses.each_with_object({}) { |status, memo| memo[status] = true }.freeze
    end

    # Nokogiri 1.12 split the HTML4 parser out of the `Nokogiri::HTML`
    # shortcut; `Nokogiri::HTML4` is the non-deprecated entry point where
    # it exists.
    HTML_PARSER = if defined?(::Nokogiri::HTML4) && ::Nokogiri::HTML4.respond_to?(:parse)
                    ::Nokogiri::HTML4
                  else
                    ::Nokogiri::HTML
                  end

    # Nokogiri on JRuby is backed by Xerces/NekoHTML rather than libxml2.
    # It does not sniff the `<meta charset>` declaration as reliably, so we
    # give the parser an explicit fallback encoding there instead of `nil`.
    JRUBY = defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

    DEFAULT_ENCODING = 'UTF-8'

    CHARSET_PATTERN = /;\s*charset\s*=\s*"?([^";,\s]+)"?/i.freeze

    SUPPORTED_OPTIONS = [:css, :xpath].freeze

    def initialize(app, opts = {}, &block)
      @app   = app
      @opts  = opts.reject { |key, _value| !SUPPORTED_OPTIONS.include?(key) }
      @block = block
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers = wrap_headers(headers)

      return [status, headers, body] unless should_process?(status, headers, body)

      encoding = charset_for(headers)
      content  = read_body(body, encoding)

      doc = HTML_PARSER.parse(content, nil, parser_encoding(encoding))
      process_nodes(doc)

      content = render(doc, encoding)

      store_header(headers, CONTENT_LENGTH, content.bytesize.to_s)

      [status, headers, [content]]
    end

    def should_process?(status, headers, body = nil)
      return false if @block.nil?
      return false if NO_ENTITY_BODY_STATUSES.key?(status.to_i)
      return false if streaming_body?(body)
      return false if fetch_header(headers, TRANSFER_ENCODING)

      content_type = fetch_header(headers, CONTENT_TYPE)
      !content_type.nil? && content_type.include?('text/html')
    end

    # Kept for backwards compatibility: pre-3.x callers passed the raw body
    # and expected a joined string back.
    def extract_content(body)
      read_body(body, nil)
    end

    def process_nodes(doc)
      nodes = ::Nokogiri::XML::NodeSet.new(doc)
      nodes += doc.css(@opts[:css])     unless @opts[:css].nil?
      nodes += doc.xpath(@opts[:xpath]) unless @opts[:xpath].nil?
      @block.call(nodes) unless nodes.empty?
    end

    private

    def wrap_headers(headers)
      headers ||= {}
      HEADERS_CLASS ? HEADERS_CLASS.new.merge(headers) : headers.dup
    end

    # `Rack::Headers` and `HeaderHash` are case-insensitive, a plain Hash is
    # not, so the lookup falls back to a scan for the unwrapped case.
    def fetch_header(headers, name)
      value = headers[name] || headers[name.downcase]
      return value unless value.nil?
      return nil if HEADERS_CLASS && headers.is_a?(HEADERS_CLASS)

      _key, found = headers.find { |key, _| key.to_s.casecmp(name).zero? }
      found
    end

    def store_header(headers, name, value)
      unless HEADERS_CLASS && headers.is_a?(HEADERS_CLASS)
        headers.delete_if { |key, _| key.to_s.casecmp(name).zero? }
      end
      headers[name] = value
    end

    # Rack 3 allows a body that responds to `call` (streaming) instead of
    # `each`. We cannot buffer that without breaking streaming semantics, so
    # such responses pass through untouched.
    def streaming_body?(body)
      return false if body.nil?

      !body.respond_to?(:each) && !body.respond_to?(:to_ary) && body.respond_to?(:call)
    end

    # Body parts are byte strings, so they are collected in a binary buffer
    # and only then tagged with the response encoding. Concatenating into a
    # UTF-8 buffer would raise `Encoding::CompatibilityError` on any body
    # that arrives as ASCII-8BIT with high bytes.
    def read_body(body, encoding)
      buffer = String.new.force_encoding(Encoding::BINARY)

      parts = body.respond_to?(:to_ary) ? body.to_ary : body
      parts.each { |part| buffer << part.to_s.b }

      buffer.force_encoding(encoding || Encoding::BINARY)
      buffer.valid_encoding? ? buffer : buffer.force_encoding(Encoding::BINARY)
    ensure
      body.close if body.respond_to?(:close)
    end

    def charset_for(headers)
      content_type = fetch_header(headers, CONTENT_TYPE).to_s
      match = CHARSET_PATTERN.match(content_type)
      return nil if match.nil?

      Encoding.find(match[1])
    rescue ArgumentError
      nil
    end

    def parser_encoding(encoding)
      return encoding.to_s unless encoding.nil?

      # No declared charset: libxml2 sniffs the document itself, the Java
      # backend needs to be told.
      JRUBY ? DEFAULT_ENCODING : nil
    end

    def render(doc, encoding)
      name = (encoding || doc.encoding || DEFAULT_ENCODING).to_s
      html = doc.to_html(encoding: name)

      # The Java backend ignores the `:encoding` option in some versions and
      # hands back a UTF-8 string regardless.
      return html if html.encoding.to_s.casecmp(name).zero?

      html.encode(name, invalid: :replace, undef: :replace)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError, ArgumentError
      doc.to_html
    end

  end
end
