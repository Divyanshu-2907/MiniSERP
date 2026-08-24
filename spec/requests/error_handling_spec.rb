# frozen_string_literal: true

require "rails_helper"

# These examples simulate production, where the StandardError catch-all
# actually renders instead of re-raising. The original bug was invisible in
# dev/test because the catch-all was only registered outside local envs, so the
# suite never exercised the handler chain production actually ran.
RSpec.describe "error handling in a production-like environment", type: :request do
  before { allow(Rails.env).to receive(:local?).and_return(false) }

  it "still maps a blocked scrape to 403, not the catch-all 500" do
    get "/search", params: { q: "captcha please" }, headers: auth_headers

    expect(response).to have_http_status(:forbidden)
    expect(json_body["error"]).to eq("blocked")
  end

  it "still maps a blank query to 400" do
    get "/search", headers: auth_headers

    expect(response).to have_http_status(:bad_request)
    expect(json_body["error"]).to eq("invalid_query")
  end

  it "still maps an unknown engine to 400" do
    get "/search", params: { q: "ruby", engine: "altavista" }, headers: auth_headers

    expect(response).to have_http_status(:bad_request)
    expect(json_body["error"]).to eq("unsupported_engine")
  end

  it "still serves a successful search" do
    get "/search", params: { q: "ruby on rails" }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(json_body["results_count"]).to eq(3)
  end

  it "renders the generic envelope for a genuinely unexpected error" do
    allow(ScraperService).to receive(:call).and_raise(RuntimeError, "boom")

    get "/search", params: { q: "ruby on rails" }, headers: auth_headers

    expect(response).to have_http_status(:internal_server_error)
    expect(json_body).to eq(
      "error" => "internal_error",
      "message" => "something went wrong on our side"
    )
  end

  it "does not leak the underlying exception message to the caller" do
    allow(ScraperService).to receive(:call).and_raise(RuntimeError, "mongodb://user:password@host")

    get "/search", params: { q: "ruby on rails" }, headers: auth_headers

    expect(response.body).not_to include("password")
  end

  describe "handler registration order" do
    it "registers the broadest handler first so specific handlers win" do
      handled = ApplicationController.rescue_handlers.map(&:first)

      expect(handled.first).to eq("StandardError")
      expect(handled).to include("Scraper::Errors::Base")
      expect(handled.index("StandardError")).to be < handled.index("Scraper::Errors::Base")
    end
  end
end
