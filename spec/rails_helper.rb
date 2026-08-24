# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

# The suite must never reach a real search engine. Set the transport to fixture
# mode before the app boots so nothing can read a stray MINISERP_SOURCE=live
# from a developer's .env.
ENV["MINISERP_SOURCE"] = "fixture"
ENV["MINISERP_API_KEYS"] = "test-key,second-key"
ENV["MINISERP_HTTP_RETRY_BACKOFF"] = "0"

require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"

# Belt and braces: WebMock blocks every outbound connection except the local
# MongoDB the suite genuinely needs.
WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FixtureHelpers
  config.include ApiHelpers, type: :request

  # Mongoid has no transactional-fixture equivalent, so drop the collections
  # between examples instead.
  config.before(:each) do
    Mongoid.purge!
    MiniSerp.config.reset!
  end

  # Rack::Attack is disabled globally in test (see its initializer) and turned
  # on only for the examples tagged :rate_limited.
  config.around(:each, :rate_limited) do |example|
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    example.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end
end
