# frozen_string_literal: true

require "rails_helper"

# Regression guard for a production outage: every search returned 500 because
# Mongo::Auth::Unauthorized does not descend from Mongo::Error, so the cache
# rescue did not catch it. Bad cache credentials must degrade to a cache miss,
# not take the whole API down.
RSpec.describe "cache resilience", type: :request do
  def auth_error
    Mongo::Auth::Unauthorized.new(
      Mongo::Auth::User.new(user: "u", password: "p", database: "miniserp_test")
    )
  end

  it "confirms the trap: auth errors are not Mongo::Error" do
    expect(Mongo::Auth::Unauthorized.ancestors).not_to include(Mongo::Error)
    expect(Mongo::Auth::Unauthorized.ancestors).to include(Mongo::Error::AuthError)
  end

  it "lists every cache failure it intends to survive" do
    expect(ScraperService::CACHE_ERRORS).to include(Mongo::Error::AuthError)
  end

  describe "when the cache read fails to authenticate" do
    before { allow(SearchResult).to receive(:fresh).and_raise(auth_error) }

    it "still serves scraped results instead of a 500" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(json_body["results_count"]).to eq(3)
      expect(json_body["cached"]).to be(false)
    end
  end

  describe "when the cache write fails to authenticate" do
    before { allow(SearchResult).to receive(:create!).and_raise(auth_error) }

    it "still returns the freshly scraped results" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(json_body["results_count"]).to eq(3)
    end
  end

  describe "when Mongo is unreachable entirely" do
    before do
      allow(SearchResult).to receive(:fresh)
        .and_raise(Mongo::Error::SocketError, "connection refused")
    end

    it "degrades to a cache miss" do
      get "/search", params: { q: "ruby on rails" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(json_body["cached"]).to be(false)
    end
  end
end
