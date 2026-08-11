# frozen_string_literal: true

require File.expand_path('../spec_helper', __FILE__)

describe Rack::Nokogiri do

  let(:app) do
    create_app(status, headers, content, opts) do |nodes|
      nodes.wrap('<div class="greeting"></div>')
    end
  end

  describe 'with a content-type other than `text/html`' do

    before { get '/' }

    let(:status) { 200 }
    let(:headers) do
      {
        header_name('Content-Type')   => 'text/plain',
        header_name('Content-Length') => content.length.to_s
      }
    end

    let(:content) { 'foobar' }
    let(:opts) { {} }

    it 'leaves the status untouched' do
      _(last_response.status).must_equal status
    end

    it 'leaves the headers untouched' do
      _(normalize_headers(last_response.headers)).must_equal normalize_headers(headers)
    end

    it 'leaves the content untouched' do
      _(last_response.body).must_equal content
    end

  end

  describe 'with a content-type of `text/html`' do

    before { get '/' }

    let(:status) { 200 }
    let(:headers) do
      {
        header_name('Content-Type')   => 'text/html',
        header_name('Content-Length') => content.length.to_s
      }
    end

    let(:content) do
      <<-eos
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <title>Some HTML</title>
        </head>

        <body>
          <p class="hi">Hi!</p>
          <p class="bye">Bye!</p>
        </body>
      </html>
      eos
    end

    describe 'with a CSS selector' do
      let(:opts) { { css: 'p.hi' } }

      it 'leaves the status untouched' do
        _(last_response.status).must_equal status
      end

      it 'updates the headers with the new `Content-Length`' do
        _(normalize_headers(last_response.headers)).wont_equal normalize_headers(headers)
        _(last_response.headers['content-length']).must_equal last_response.body.bytesize.to_s
      end

      it 'executes the block on the results of the selector' do
        _(last_response.body).must_have_css '.greeting .hi'
        _(last_response.body).wont_have_css '.greeting .bye'
      end
    end

    describe 'with a XPath selector' do
      let(:opts) { { xpath: "//p[@class='hi']" } }

      it 'leaves the status untouched' do
        _(last_response.status).must_equal status
      end

      it 'updates the headers with the new `Content-Length`' do
        _(normalize_headers(last_response.headers)).wont_equal normalize_headers(headers)
      end

      it 'executes the block on the results of the selector' do
        _(last_response.body).must_have_xpath "//div[@class='greeting']/p[@class='hi']"
        _(last_response.body).wont_have_xpath "//div[@class='greeting']/p[@class='bye']"
      end
    end

    describe 'with an unsupported option' do
      let(:opts) { { css: 'p.hi', foo: 'bar' } }

      it 'ignores it' do
        _(last_response.body).must_have_css '.greeting .hi'
      end
    end

  end

  describe 'with a status that carries no entity body' do

    # A 204 carrying a Content-Type and a body is not a legal Rack response, so
    # this one bypasses Rack::Lint: what is under test is that the middleware
    # declines to touch it, not that the fixture is well-formed.
    let(:app) do
      create_raw_app(status, headers, content, opts) do |nodes|
        nodes.wrap('<div class="greeting"></div>')
      end
    end

    before { get '/' }

    let(:status)  { 204 }
    let(:headers) { { header_name('Content-Type') => 'text/html' } }
    let(:content) { '<p class="hi">Hi!</p>' }
    let(:opts)    { { css: 'p.hi' } }

    it 'leaves the content untouched' do
      _(last_response.body).must_equal content
    end

  end

  describe 'with a `Transfer-Encoding` header' do

    before { get '/' }

    let(:status) { 200 }
    let(:headers) do
      {
        header_name('Content-Type')      => 'text/html',
        header_name('Transfer-Encoding') => 'chunked'
      }
    end

    let(:content) { '<p class="hi">Hi!</p>' }
    let(:opts)    { { css: 'p.hi' } }

    it 'leaves the content untouched' do
      _(last_response.body).must_equal content
    end

  end

  describe 'without a block' do

    let(:app) do
      create_app(200, { header_name('Content-Type') => 'text/html' },
                 '<p class="hi">Hi!</p>', css: 'p.hi')
    end

    before { get '/' }

    it 'leaves the content untouched' do
      _(last_response.body).must_equal '<p class="hi">Hi!</p>'
    end

  end

  describe 'with a declared charset' do

    let(:body) { '<html><body><p class="hi">Ünïcødé</p></body></html>' }

    let(:app) do
      inner = lambda do |_env|
        [200,
         { header_name('Content-Type') => 'text/html; charset=iso-8859-1' },
         [body.encode(Encoding::ISO_8859_1)]]
      end
      Rack::Nokogiri.new(inner, css: 'p.hi') do |nodes|
        nodes.wrap('<div class="greeting"></div>')
      end
    end

    before { get '/' }

    it 'round-trips the content in the declared encoding' do
      round_tripped = last_response.body.dup.force_encoding(Encoding::ISO_8859_1)
      _(round_tripped.valid_encoding?).must_equal true
      _(round_tripped.encode(Encoding::UTF_8)).must_include 'Ünïcødé'
    end

    it 'reports a byte-accurate `Content-Length`' do
      _(last_response.headers['content-length']).must_equal last_response.body.bytesize.to_s
    end

  end

  describe 'with a binary body and no declared charset' do

    let(:app) do
      inner = lambda do |_env|
        payload = '<html><body><p class="hi">Ünïcødé</p></body></html>'.dup.b
        [200, { header_name('Content-Type') => 'text/html' }, [payload]]
      end
      Rack::Nokogiri.new(inner, css: 'p.hi') do |nodes|
        nodes.wrap('<div class="greeting"></div>')
      end
    end

    before { get '/' }

    it 'processes it without raising an encoding error' do
      _(last_response.status).must_equal 200
      _(last_response.body).must_have_css '.greeting .hi'
    end

  end

  describe 'with a closeable body' do

    let(:closed) { [] }

    let(:app) do
      body = Object.new
      tracker = closed
      body.define_singleton_method(:each) { |&blk| blk.call('<p class="hi">Hi!</p>') }
      body.define_singleton_method(:close) { tracker << true }

      inner = lambda { |_env| [200, { header_name('Content-Type') => 'text/html' }, body] }
      Rack::Nokogiri.new(inner, css: 'p.hi') do |nodes|
        nodes.wrap('<div class="greeting"></div>')
      end
    end

    it 'closes the original body it replaces' do
      get '/'
      _(closed).must_equal [true]
      _(last_response.body).must_have_css '.greeting .hi'
    end

  end

  describe 'when the selector matches nothing' do

    let(:content) { '<html><body><p class="hi">Hi!</p></body></html>' }

    let(:app) do
      inner = lambda do |_env|
        [200,
         { header_name('Content-Type')   => 'text/html',
           header_name('Content-Length') => content.bytesize.to_s },
         [content]]
      end
      Rack::Nokogiri.new(inner, css: 'p.nope') { |nodes| nodes.wrap('<div></div>') }
    end

    before { get '/' }

    # Round-tripping through Nokogiri normalises the markup, so a response the
    # block never touched must not be re-serialised at all.
    it 'returns the body byte for byte' do
      _(last_response.body).must_equal content
    end

    it 'does not inject a doctype' do
      _(last_response.body).wont_match(/DOCTYPE/i)
    end

    it 'leaves the `Content-Length` alone' do
      _(last_response.headers['content-length']).must_equal content.bytesize.to_s
    end

  end

  describe 'with `fragment: true`' do

    let(:app) do
      inner = lambda do |_env|
        [200, { header_name('Content-Type') => 'text/html' }, ['<p class="hi">Hi!</p>']]
      end
      Rack::Nokogiri.new(inner, css: 'p.hi', fragment: true) do |nodes|
        nodes.wrap('<div class="greeting"></div>')
      end
    end

    before { get '/' }

    it 'edits the fragment without wrapping it in a document' do
      _(last_response.body).must_equal '<div class="greeting"><p class="hi">Hi!</p></div>'
    end

    it 'does not inject a doctype' do
      _(last_response.body).wont_match(/DOCTYPE/i)
    end

  end

  describe 'with a HEAD request' do

    let(:app) do
      inner = lambda do |_env|
        [200, { header_name('Content-Type') => 'text/html' }, []]
      end
      Rack::Nokogiri.new(inner, css: 'p.hi') { |nodes| nodes.wrap('<div></div>') }
    end

    # A HEAD response carries its GET counterpart's headers but no body;
    # serialising a parsed empty document would invent one.
    it 'does not invent a body' do
      head '/'
      _(last_response.body).must_equal ''
      # Rack 3's test harness stamps a `0` here; either way it must not be the
      # length of a serialised empty document.
      _(['0', nil]).must_include last_response.headers['content-length']
    end

  end

  describe 'with a `Content-Encoding` header' do

    let(:compressed) do
      buffer = StringIO.new
      gzip   = Zlib::GzipWriter.new(buffer)
      gzip.write('<html><body><p class="hi">Hi!</p></body></html>')
      gzip.close
      buffer.string
    end

    let(:app) do
      payload = compressed
      inner = lambda do |_env|
        [200,
         { header_name('Content-Type')     => 'text/html',
           header_name('Content-Encoding') => 'gzip' },
         [payload]]
      end
      Rack::Nokogiri.new(inner, css: 'p.hi') { |nodes| nodes.wrap('<div></div>') }
    end

    before { get '/' }

    # A gzipped body is not HTML; parsing it yields garbage and re-serialising
    # destroys the response.
    it 'leaves the compressed body intact' do
      round_tripped = Zlib::GzipReader.new(StringIO.new(last_response.body.b)).read
      _(round_tripped).must_include '<p class="hi">Hi!</p>'
    end

  end

  describe 'with an array of selectors' do

    let(:status)  { 200 }
    let(:headers) { { header_name('Content-Type') => 'text/html' } }
    let(:content) { '<html><body><p class="a">A</p><p class="b">B</p></body></html>' }
    let(:opts)    { { css: ['p.a', 'p.b'] } }

    before { get '/' }

    it 'applies the block to everything they match' do
      _(last_response.body.scan(/class="greeting"/).length).must_equal 2
    end

  end

  describe 'with several rules' do

    let(:app) do
      inner = lambda do |_env|
        [200,
         { header_name('Content-Type') => 'text/html' },
         ['<html><body><p class="a">A</p><p class="b">B</p></body></html>']]
      end
      middleware = Rack::Nokogiri.new(
        inner,
        rules: [
          { css: 'p.a',   with: ->(nodes) { nodes.wrap('<div class="one"></div>') } },
          { xpath: "//p[@class='b']", with: ->(nodes) { nodes.each { |n| n.content = 'edited' } } }
        ]
      )
      Rack::Lint.new(middleware)
    end

    before { get '/' }

    it 'runs each rule against its own selector' do
      _(last_response.body).must_have_css 'div.one p.a'
      _(last_response.body).must_include 'edited'
    end

    it 'leaves the other rule\'s nodes alone' do
      _(last_response.body).wont_have_css 'div.one p.b'
    end

  end

  describe 'with a custom `content_type`' do

    let(:status)  { 200 }
    let(:headers) { { header_name('Content-Type') => 'application/xhtml+xml' } }
    let(:content) { '<html><body><p class="hi">Hi!</p></body></html>' }
    let(:opts)    { { css: 'p.hi', content_type: %r{application/xhtml\+xml} } }

    before { get '/' }

    it 'processes a type it would otherwise skip' do
      _(last_response.body).must_have_css '.greeting .hi'
    end

  end

  describe 'with `max_size`' do

    let(:status)  { 200 }
    let(:headers) { { header_name('Content-Type') => 'text/html' } }
    let(:content) { '<html><body>' + ('<p class="hi">x</p>' * 200) + '</body></html>' }

    describe 'when the body exceeds it' do
      let(:opts) { { css: 'p.hi', max_size: 64 } }

      before { get '/' }

      # Nokogiri builds a DOM several times the size of the source.
      it 'returns the body untouched' do
        _(last_response.body).must_equal content
      end
    end

    describe 'when a declared `Content-Length` exceeds it' do
      let(:headers) do
        {
          header_name('Content-Type')   => 'text/html',
          header_name('Content-Length') => content.bytesize.to_s
        }
      end

      let(:opts) { { css: 'p.hi', max_size: 64 } }

      before { get '/' }

      it 'declines before reading the body' do
        _(last_response.body).must_equal content
      end
    end

    describe 'when the body fits' do
      let(:opts) { { css: 'p.hi', max_size: 10_000_000 } }

      before { get '/' }

      it 'processes it as usual' do
        _(last_response.body).must_have_css '.greeting .hi'
      end
    end

  end

  describe 'with `parse_options`' do

    let(:status)  { 200 }
    let(:headers) { { header_name('Content-Type') => 'text/html' } }
    let(:content) { '<html><body><p class="hi">Hi!</p></body></html>' }
    let(:opts) do
      { css: 'p.hi', parse_options: Nokogiri::XML::ParseOptions::NOBLANKS }
    end

    before { get '/' }

    it 'hands them to the parser' do
      _(last_response.body).must_have_css '.greeting .hi'
    end

  end

  describe 'Rack::Lint compliance' do

    def lint(status, headers, body, opts = { css: 'p.hi' })
      inner = lambda { |_env| [status, headers, body] }
      middleware = Rack::Nokogiri.new(inner, opts) { |nodes| nodes.wrap('<div></div>') }
      Rack::Lint.new(middleware)
    end

    let(:html) { '<html><body><p class="hi">Hi!</p></body></html>' }

    let(:headers) do
      { header_name('Content-Type') => 'text/html' }
    end

    it 'emits a valid response when it rewrites the body' do
      response = Rack::MockRequest.new(lint(200, headers, [html])).get('/')
      _(response.status).must_equal 200
      _(response.body).must_have_css '.greeting, div p.hi'
    end

    it 'emits a valid response when it passes the body through' do
      response = Rack::MockRequest.new(lint(200, headers, [html], css: 'p.nope')).get('/')
      _(response.body).must_equal html
    end

    it 'emits a valid response to a HEAD request' do
      response = Rack::MockRequest.new(lint(200, headers, [])).head('/')
      _(response.body).must_equal ''
    end

  end

  describe 'with a streaming body' do

    let(:app) do
      body = Object.new
      body.define_singleton_method(:call) { |_stream| nil }

      inner = lambda { |_env| [200, { header_name('Content-Type') => 'text/html' }, body] }
      Rack::Nokogiri.new(inner, css: 'p.hi') do |nodes|
        nodes.wrap('<div class="greeting"></div>')
      end
    end

    it 'passes it through untouched' do
      status, _headers, returned = app.call(Rack::MockRequest.env_for('/'))
      _(status).must_equal 200
      _(returned.respond_to?(:call)).must_equal true
    end

  end

end
