source 'https://rubygems.org'

# Specify your gem's dependencies in rack-nokogiri.gemspec
gemspec

# Optional: prettier test output, and file watching for `guard`. Neither is
# available on every platform/engine, so they stay out of the gemspec.
group :development do
  gem 'minitest-reporters', require: false
  gem 'guard-minitest',     require: false
  gem 'rb-inotify',         require: false, platforms: [:ruby]
  gem 'rb-fsevent',         require: false, platforms: [:ruby]
end
