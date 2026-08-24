# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScraperService do
  let(:exploding_client) do
    Class.new do
      def get(*, **)
        raise "the network must not be used on a cache hit"
      end
    end.new
  end

  describe "a successful scrape" do
    subject(:result) do
      described_class.call(query: "ruby on rails", engine: "google", client: stub_client("google_classic.html"))
    end

    it "returns parsed results" do
      expect(result.count).to eq(3)
      expect(result.results.first[:title]).to eq("Ruby on Rails — A web-app framework")
    end

    it "is not marked as cached" do
      expect(result).not_to be_cached
    end

    it "records the scrape time" do
      expect(result.scraped_at).to be_within(5.seconds).of(Time.current)
    end

    it "persists a SearchResult document" do
      expect { result }.to change(SearchResult, :count).by(1)

      record = SearchResult.last
      expect(record.query).to eq("ruby on rails")
      expect(record.engine).to eq("google")
      expect(record.results.length).to eq(3)
      expect(record.results.first["link"]).to eq("https://rubyonrails.org/")
    end
  end

  describe "cache behaviour" do
    before do
      SearchResult.create!(
        query: "ruby on rails",
        engine: "google",
        scraped_at: 5.minutes.ago,
        results: [ { "position" => 1, "title" => "Cached hit", "link" => "https://example.com", "snippet" => "from mongo" } ]
      )
    end

    it "serves a fresh cached document without scraping" do
      result = described_class.call(query: "ruby on rails", engine: "google", client: exploding_client)

      expect(result).to be_cached
      expect(result.results.first[:title]).to eq("Cached hit")
    end

    it "reports how old the cached document is" do
      result = described_class.call(query: "ruby on rails", engine: "google", client: exploding_client)

      expect(result.cache_age_seconds).to be_within(5).of(300)
    end

    it "returns symbol-keyed rows, exactly like a live scrape" do
      result = described_class.call(query: "ruby on rails", engine: "google", client: exploding_client)

      expect(result.results.first.keys).to match_array(%i[position title link snippet])
    end

    it "writes no new document on a cache hit" do
      expect do
        described_class.call(query: "ruby on rails", engine: "google", client: exploding_client)
      end.not_to change(SearchResult, :count)
    end

    it "re-scrapes when the cached document is older than the TTL" do
      SearchResult.first.update!(scraped_at: 7.hours.ago)

      result = described_class.call(
        query: "ruby on rails", engine: "google",
        client: stub_client("google_classic.html"), ttl_hours: 6
      )

      expect(result).not_to be_cached
      expect(result.results.first[:title]).to eq("Ruby on Rails — A web-app framework")
    end

    it "bypasses the cache when refresh is requested" do
      result = described_class.call(
        query: "ruby on rails", engine: "google",
        refresh: true, client: stub_client("google_classic.html")
      )

      expect(result).not_to be_cached
      expect(SearchResult.count).to eq(2)
    end

    it "does not read the cache when the TTL is zero" do
      result = described_class.call(
        query: "ruby on rails", engine: "google",
        client: stub_client("google_classic.html"), ttl_hours: 0
      )

      expect(result).not_to be_cached
    end
  end

  describe "block detection" do
    it "raises Blocked when the engine serves a captcha page" do
      expect do
        described_class.call(query: "ruby", engine: "google", client: stub_client("google_captcha.html"))
      end.to raise_error(Scraper::Errors::Blocked, /anti-bot/)
    end

    it "caches nothing when blocked" do
      expect do
        described_class.call(query: "ruby", engine: "google", client: stub_client("google_captcha.html"))
      rescue Scraper::Errors::Blocked
        nil
      end.not_to change(SearchResult, :count)
    end
  end

  describe "empty result sets" do
    subject(:result) do
      described_class.call(query: "zznomatch", engine: "google", client: stub_client("google_empty.html"))
    end

    it "succeeds with zero results rather than raising" do
      expect(result).to be_empty
      expect(result.count).to eq(0)
    end

    it "caches the empty result so the query is not re-scraped" do
      expect { result }.to change(SearchResult, :count).by(1)
    end
  end

  describe "input validation" do
    it "rejects a blank query" do
      expect { described_class.call(query: "  ", engine: "google") }
        .to raise_error(Scraper::Errors::InvalidQuery)
    end

    it "rejects an unknown engine" do
      expect { described_class.call(query: "ruby", engine: "altavista") }
        .to raise_error(Scraper::Errors::UnsupportedEngine, /supported: google/)
    end

    it "defaults to google when no engine is given" do
      result = described_class.call(query: "ruby", client: stub_client("google_classic.html"))

      expect(result.engine).to eq("google")
    end
  end

  describe "transport selection" do
    it "uses the offline fixture client unless MINISERP_SOURCE is live" do
      expect(described_class.default_client).to be_a(Scraper::FixtureClient)
    end

    it "uses the live HTTP client when explicitly configured" do
      allow(MiniSerp.config).to receive(:live?).and_return(true)

      expect(described_class.default_client).to be_a(Scraper::Client)
    end
  end
end
