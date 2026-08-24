# frozen_string_literal: true

module Scraper
  # Offline transport: serves saved HTML instead of calling a search engine.
  #
  # This is the default in every environment. Scraping Google/Bing live breaks
  # their Terms of Service and gets IPs flagged, and none of the interesting
  # engineering (parsing, caching, block detection, error handling) needs a
  # real request to exercise it.
  #
  # It deliberately implements the exact same #get contract as Scraper::Client,
  # so swapping transports changes nothing above this layer.
  class FixtureClient
    DEFAULT_FIXTURE = "google_classic.html"

    # Query patterns mapped to fixtures, so the demo curl calls in the README
    # can walk through every code path without touching the network.
    ROUTES = [
      [ /captcha|blocked|sorry|unusual traffic/i, "google_captcha.html" ],
      [ /\bempty\b|no.?results|zznomatch/i,       "google_empty.html" ],
      [ /nokogiri/i,                              "google_new_layout.html" ]
    ].freeze

    def initialize(fixture_dir: nil, fixture: nil, logger: nil)
      @fixture_dir = fixture_dir || MiniSerp.config.fixture_dir
      @fixture     = fixture || MiniSerp.config.forced_fixture
      @logger      = logger || Rails.logger
    end

    def get(url, headers: {}) # rubocop:disable Lint/UnusedMethodArgument
      name = fixture_name_for(url)
      path = Pathname.new(@fixture_dir).join(name)

      unless path.file?
        raise Errors::RequestFailed, "fixture not found: #{path} (set MINISERP_SOURCE=live or add the file)"
      end

      @logger&.info("[scraper] fixture mode: #{name} for #{url}")

      Response.new(
        body: path.read,
        status: 200,
        url: url,
        headers: { "content-type" => "text/html; charset=UTF-8", "x-miniserp-fixture" => name }
      )
    end

    private

    def fixture_name_for(url)
      return @fixture if @fixture.present?

      query = extract_query(url)
      match = ROUTES.find { |pattern, _| pattern.match?(query) }
      match ? match.last : DEFAULT_FIXTURE
    end

    def extract_query(url)
      URI.decode_www_form(URI.parse(url.to_s).query.to_s).to_h.fetch("q", "").to_s
    rescue URI::InvalidURIError, ArgumentError
      ""
    end
  end
end
