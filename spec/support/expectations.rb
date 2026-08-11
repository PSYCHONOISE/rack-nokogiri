# frozen_string_literal: true

module Minitest::Assertions

  def assert_has_css(html, css)
    assert ::Nokogiri::HTML(html).css(css).length > 0,
      "Expected HTML to produce results for CSS selector `#{css}`"
  end

  def refute_has_css(html, css)
    refute ::Nokogiri::HTML(html).css(css).length > 0,
      "Expected HTML to produce no results for CSS selector `#{css}`"
  end

  def assert_has_xpath(html, xpath)
    assert ::Nokogiri::HTML(html).xpath(xpath).length > 0,
      "Expected HTML to produce results for XPath selector `#{xpath}`"
  end

  def refute_has_xpath(html, xpath)
    refute ::Nokogiri::HTML(html).xpath(xpath).length > 0,
      "Expected HTML to produce no results for XPath selector `#{xpath}`"
  end

end

# Minitest 6 moved `infect_an_assertion` onto `Minitest::Expectations`; in
# Minitest 5 it is a private `Module` method used from inside the module body.
INFECTIONS = [
  [:assert_has_css,   :must_have_css],
  [:refute_has_css,   :wont_have_css],
  [:assert_has_xpath, :must_have_xpath],
  [:refute_has_xpath, :wont_have_xpath]
].freeze

if Minitest::Expectations.respond_to?(:infect_an_assertion, true)
  INFECTIONS.each do |assertion, expectation|
    Minitest::Expectations.send(:infect_an_assertion, assertion, expectation, :reverse)
  end
else
  module Minitest::Expectations
    INFECTIONS.each do |assertion, expectation|
      infect_an_assertion assertion, expectation, :reverse
    end
  end
end
