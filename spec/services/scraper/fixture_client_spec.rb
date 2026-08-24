# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::FixtureClient do
  subject(:client) { described_class.new }

  def get(query)
    client.get("https://www.google.com/search?#{{ q: query }.to_query}")
  end

  it "serves the default results page" do
    expect(get("ruby on rails").body).to include("Ruby on Rails Guides")
  end

  it "routes a captcha-flavoured query to the block page" do
    expect(get("captcha").body).to include("unusual traffic")
  end

  it "routes an empty-flavoured query to the no-results page" do
    expect(get("zznomatch").body).to include("did not match any documents")
  end

  it "honours a forced fixture regardless of query" do
    forced = described_class.new(fixture: "google_new_layout.html")

    expect(forced.get("https://www.google.com/search?q=anything").body).to include("Nokogiri")
  end

  it "raises a clear error when the fixture is missing" do
    missing = described_class.new(fixture: "does_not_exist.html")

    expect { missing.get("https://www.google.com/search?q=x") }
      .to raise_error(Scraper::Errors::RequestFailed, /fixture not found/)
  end

  it "never touches the network" do
    expect { get("ruby") }.not_to raise_error
    expect(WebMock).not_to have_requested(:any, /google\.com/)
  end
end
