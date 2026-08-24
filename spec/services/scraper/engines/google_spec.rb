# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Engines::Google do
  subject(:engine) { described_class.new }

  describe "#search_url" do
    it "builds an encoded google search URL" do
      url = engine.search_url("ruby on rails", limit: 10)

      expect(url).to start_with("https://www.google.com/search?")
      expect(url).to include("q=ruby+on+rails")
      expect(url).to include("num=10")
    end

    it "clamps an absurd limit into google's accepted range" do
      expect(engine.search_url("ruby", limit: 5_000)).to include("num=100")
    end
  end

  describe "#parse on the classic div.g layout" do
    let(:results) { engine.parse(fixture_document("google_classic.html")) }

    it "extracts every organic result" do
      expect(results.length).to eq(3)
    end

    it "returns title, link, snippet and a 1-based position for each" do
      expect(results.first).to eq(
        position: 1,
        title: "Ruby on Rails — A web-app framework",
        link: "https://rubyonrails.org/",
        snippet: "Ruby on Rails is a full-stack framework. It ships with all the tools " \
                 "needed to build amazing web apps on both the front and back end."
      )
    end

    it "unwraps google's /url?q= redirect wrapper" do
      expect(results[1][:link]).to eq("https://guides.rubyonrails.org/")
    end

    it "numbers results consecutively" do
      expect(results.map { |r| r[:position] }).to eq([ 1, 2, 3 ])
    end

    it "skips non-organic blocks such as People Also Ask" do
      expect(results.map { |r| r[:title] }).not_to include(a_string_matching(/People also ask/i))
    end

    it "honours the limit" do
      expect(engine.parse(fixture_document("google_classic.html"), limit: 2).length).to eq(2)
    end
  end

  describe "#parse on the newer div.MjjYud layout" do
    let(:results) { engine.parse(fixture_document("google_new_layout.html")) }

    # This is the regression guard for the selector break described in the
    # README's engineering notes: the page has no div.g at all.
    it "falls through to the next container strategy when div.g is absent" do
      expect(fixture_document("google_new_layout.html").css("div.g")).to be_empty
      expect(results.length).to eq(2)
    end

    it "still extracts a usable result" do
      expect(results.first).to include(
        position: 1,
        title: "Nokogiri",
        link: "https://nokogiri.org/"
      )
      expect(results.first[:snippet]).to include("HTML, XML, SAX, and Reader parser")
    end
  end

  describe "#parse when the layout is unrecognised" do
    it "raises rather than returning silently-empty results" do
      document = Nokogiri::HTML("<html><body><div id='search'><p>nothing here</p></div></body></html>")

      expect { engine.parse(document) }.to raise_error(Scraper::Errors::ParseFailed, /stale/)
    end

    it "recovers structurally when only the class names changed" do
      html = <<~HTML
        <html><body><div id="search"><div id="rso">
          <div class="totally-new-class">
            <a href="https://example.com/a"><h3>Example A</h3></a>
            <div class="VwiC3b">A snippet.</div>
          </div>
        </div></div></body></html>
      HTML

      results = engine.parse(Nokogiri::HTML(html))

      expect(results.first).to include(title: "Example A", link: "https://example.com/a")
    end
  end

  describe "#blocked?" do
    it "detects the unusual-traffic interstitial" do
      expect(engine.blocked?(fixture_response("google_captcha.html"))).to be(true)
    end

    it "does not flag a normal results page" do
      expect(engine.blocked?(fixture_response("google_classic.html"))).to be(false)
    end

    it "detects a captcha form even when the copy is localised" do
      html = "<html><body><h1>Bestätigung</h1><form action='/sorry/index'></form></body></html>"
      response = Scraper::Response.new(body: html, status: 200, url: "https://www.google.com/sorry/index")

      expect(engine.blocked?(response)).to be(true)
    end
  end

  describe "#no_results?" do
    it "recognises google's explicit no-match copy" do
      expect(engine.no_results?(fixture_document("google_empty.html"))).to be(true)
    end

    it "is false for a page that has results" do
      expect(engine.no_results?(fixture_document("google_classic.html"))).to be(false)
    end
  end

  describe "empty result sets" do
    it "returns an empty array instead of raising" do
      expect(engine.parse(fixture_document("google_empty.html"))).to eq([])
    end
  end
end
