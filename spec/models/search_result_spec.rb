# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchResult do
  def create_result(query:, engine: "google", scraped_at: Time.current, results: [])
    described_class.create!(query: query, engine: engine, scraped_at: scraped_at, results: results)
  end

  describe ".cache_key_for" do
    it "collapses surrounding and repeated whitespace" do
      expect(described_class.cache_key_for("  ruby   on  rails ")).to eq("ruby on rails")
    end

    it "preserves case, so differently-cased queries are distinct cache entries" do
      expect(described_class.cache_key_for("Ruby on Rails")).to eq("Ruby on Rails")
    end
  end

  describe "#assign_query_key" do
    it "is derived from the query on save" do
      record = create_result(query: "  ruby   on rails ")

      expect(record.query_key).to eq("ruby on rails")
    end
  end

  describe ".fresh" do
    it "finds a record whose whitespace differs from the lookup query" do
      create_result(query: "ruby on rails", scraped_at: 10.minutes.ago)

      found = described_class.fresh(query: "ruby   on rails", engine: "google", ttl_hours: 6)

      expect(found).to be_present
    end

    it "ignores records older than the TTL" do
      create_result(query: "ruby on rails", scraped_at: 7.hours.ago)

      found = described_class.fresh(query: "ruby on rails", engine: "google", ttl_hours: 6)

      expect(found).to be_nil
    end

    it "returns the newest record when several are fresh" do
      create_result(query: "ruby", scraped_at: 30.minutes.ago, results: [ { "title" => "older" } ])
      create_result(query: "ruby", scraped_at: 2.minutes.ago,  results: [ { "title" => "newer" } ])

      found = described_class.fresh(query: "ruby", engine: "google", ttl_hours: 6)

      expect(found.results.first["title"]).to eq("newer")
    end

    it "does not cross engine boundaries" do
      create_result(query: "ruby", engine: "bing", scraped_at: 1.minute.ago)

      found = described_class.fresh(query: "ruby", engine: "google", ttl_hours: 6)

      expect(found).to be_nil
    end

    it "returns nil when caching is disabled with a zero TTL" do
      create_result(query: "ruby", scraped_at: 1.second.ago)

      found = described_class.fresh(query: "ruby", engine: "google", ttl_hours: 0)

      expect(found).to be_nil
    end
  end

  describe "#age_seconds" do
    it "reports how stale the cached document is" do
      record = create_result(query: "ruby", scraped_at: 90.seconds.ago)

      expect(record.age_seconds).to be_within(2).of(90)
    end
  end
end
