source "https://rubygems.org"

gem "rails", "~> 8.1.3", ">= 8.1.3.1"

# Web server
gem "puma", ">= 5.0"

# --- MiniSERP core dependencies -------------------------------------------
# MongoDB ODM (this app uses Mongoid instead of Active Record)
gem "mongoid", "~> 9.0"
# HTML parsing for the scrapers
gem "nokogiri", "~> 1.18"
# HTTP client used by Scraper::Client
gem "httparty", "~> 0.22"
# Per-API-key rate limiting
gem "rack-attack", "~> 6.7"
# Load ENV vars from .env in development
gem "dotenv-rails", groups: %i[development test]
# ---------------------------------------------------------------------------

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails", "~> 8.0"
  gem "rack-test", require: "rack/test"
  gem "webmock", "~> 3.26"
  gem "rubocop-rails-omakase", require: false
end
