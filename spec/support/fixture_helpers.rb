# frozen_string_literal: true

module FixtureHelpers
  FIXTURE_DIR = Rails.root.join("spec/fixtures/html")

  def fixture_html(name)
    FIXTURE_DIR.join(name).read
  end

  def fixture_document(name)
    Nokogiri::HTML(fixture_html(name))
  end

  # A Scraper::Response backed by a saved page.
  def fixture_response(name, status: 200, url: "https://www.google.com/search?q=test")
    Scraper::Response.new(
      body: fixture_html(name),
      status: status,
      url: url,
      headers: { "content-type" => "text/html" }
    )
  end

  # A stand-in transport that always returns the given fixture, so a spec can
  # pin the exact page under test regardless of query routing.
  def stub_client(name, status: 200)
    fixture = name
    Class.new do
      define_method(:get) do |url, headers: {}|
        Scraper::Response.new(
          body: FixtureHelpers::FIXTURE_DIR.join(fixture).read,
          status: status,
          url: url,
          headers: {}
        )
      end
    end.new
  end
end
