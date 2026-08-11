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
