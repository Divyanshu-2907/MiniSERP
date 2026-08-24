# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /search", type: :request do
  describe "authentication" do
    it "rejects a request with no X-API-Key header" do
      get "/search", params: { q: "ruby on rails" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_body).to include("error" => "unauthorized")
      expect(json_body["message"]).to match(/missing X-API-Key/)
    end

    it "rejects an invalid API key" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers("nope")

      expect(response).to have_http_status(:unauthorized)
      expect(json_body).to include("error" => "unauthorized", "message" => "invalid API key")
    end

    it "rejects a blank API key" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers("   ")

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts any key configured in MINISERP_API_KEYS" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers("second-key")

      expect(response).to have_http_status(:ok)
    end

    it "does not scrape when unauthenticated" do
      expect { get "/search", params: { q: "ruby on rails" } }.not_to change(SearchResult, :count)
    end
  end

  describe "a successful search" do
    before { get "/search", params: { q: "ruby on rails" }, headers: auth_headers }

    it "responds 200 with the result envelope" do
      expect(response).to have_http_status(:ok)
      expect(json_body).to include(
        "query" => "ruby on rails",
        "engine" => "google",
        "cached" => false,
        "results_count" => 3,
        "no_results" => false
      )
    end

    it "returns clean, structured results" do
      expect(json_body["results"].first).to eq(
        "position" => 1,
        "title" => "Ruby on Rails — A web-app framework",
        "link" => "https://rubyonrails.org/",
        "snippet" => "Ruby on Rails is a full-stack framework. It ships with all the tools " \
                     "needed to build amazing web apps on both the front and back end."
      )
    end

    it "returns every result key on every row" do
      expect(json_body["results"]).to all(include("position", "title", "link", "snippet"))
    end

    it "reports an ISO-8601 scrape timestamp" do
      expect { Time.iso8601(json_body["scraped_at"]) }.not_to raise_error
    end
  end

  describe "caching across requests" do
    it "serves the second identical request from MongoDB" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers
      expect(json_body["cached"]).to be(false)

      get "/search", params: { q: "ruby on rails" }, headers: auth_headers

      expect(json_body["cached"]).to be(true)
      expect(json_body["results_count"]).to eq(3)
      expect(SearchResult.count).to eq(1)
    end

    it "re-scrapes when refresh=true" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers
      get "/search", params: { q: "ruby on rails", refresh: "true" }, headers: auth_headers

      expect(json_body["cached"]).to be(false)
      expect(SearchResult.count).to eq(2)
    end
  end

  describe "when the engine serves a captcha" do
    before { get "/search", params: { q: "captcha please" }, headers: auth_headers }

    it "responds 403 with a clear error instead of garbage results" do
      expect(response).to have_http_status(:forbidden)
      expect(json_body["error"]).to eq("blocked")
    end

    it "returns no results key full of noise" do
      expect(json_body).not_to have_key("results")
    end
  end

  describe "when the query matches nothing" do
    before { get "/search", params: { q: "zznomatch" }, headers: auth_headers }

    it "responds 200 with an explicit empty result set" do
      expect(response).to have_http_status(:ok)
      expect(json_body).to include("results_count" => 0, "no_results" => true, "results" => [])
    end
  end

  describe "invalid input" do
    it "rejects a missing query" do
      get "/search", headers: auth_headers

      expect(response).to have_http_status(:bad_request)
      expect(json_body["error"]).to eq("invalid_query")
    end

    it "rejects an unsupported engine" do
      get "/search", params: { q: "ruby", engine: "altavista" }, headers: auth_headers

      expect(response).to have_http_status(:bad_request)
      expect(json_body["error"]).to eq("unsupported_engine")
    end
  end

  describe "the versioned route" do
    it "serves the same payload at /api/v1/search" do
      get "/api/v1/search", params: { q: "nokogiri" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(json_body["results_count"]).to eq(2)
    end
  end

  describe "rate limiting", :rate_limited do
    before { allow(MiniSerp.config).to receive(:rate_limit_per_minute).and_return(2) }

    it "throttles once the per-key budget is spent" do
      2.times { get "/search", params: { q: "ruby on rails" }, headers: auth_headers }
      expect(response).to have_http_status(:ok)

      get "/search", params: { q: "ruby on rails" }, headers: auth_headers

      expect(response).to have_http_status(:too_many_requests)
      expect(json_body["error"]).to eq("rate_limit_exceeded")
      expect(response.headers["Retry-After"]).to be_present
    end

    it "budgets each API key separately" do
      2.times { get "/search", params: { q: "ruby on rails" }, headers: auth_headers("test-key") }

      get "/search", params: { q: "ruby on rails" }, headers: auth_headers("second-key")

      expect(response).to have_http_status(:ok)
    end
  end
end
