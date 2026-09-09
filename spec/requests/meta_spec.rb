# frozen_string_literal: true

require "rails_helper"

RSpec.describe "service metadata", type: :request do
  it "serves the browser demo page at the root path" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("MiniSERP")
  end

  it "describes the service as JSON at /api/v1 without a key" do
    get "/api/v1"

    expect(response).to have_http_status(:ok)
    expect(json_body).to include("service" => "miniserp", "status" => "ok")
    expect(json_body["endpoints"]).to include("search")
  end

  describe "the browser demo page" do
    let(:page) { Rails.root.join("public/index.html").read }

    # The page calls the API from the visitor's browser, so it has to agree with
    # the server on the header name and carry a key. Whether that key is
    # accepted is deployment config (MINISERP_API_KEYS), not code.
    it "sends the same header the controller reads" do
      expect(page).to include(ApiKeyAuthentication::HEADER)
    end

    it "embeds a non-empty API key" do
      key = page[/var API_KEY = "([^"]+)"/, 1]

      expect(key).to be_present
    end

    it "authenticates successfully with the key it embeds" do
      key = page[/var API_KEY = "([^"]+)"/, 1]
      allow(MiniSerp.config).to receive(:valid_api_key?).with(key).and_return(true)

      get "/search", params: { q: "ruby on rails" },
                     headers: { ApiKeyAuthentication::HEADER => key }

      expect(response).to have_http_status(:ok)
    end

    it "calls the documented search endpoint" do
      expect(page).to include("/search?q=")
    end
  end

  it "exposes the health check without a key" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end

  it "lists supported engines behind authentication" do
    get "/api/v1/engines", headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(json_body["engines"]).to eq([ "google" ])
    expect(json_body["default"]).to eq("google")
  end

  it "requires a key for the engines endpoint" do
    get "/api/v1/engines"

    expect(response).to have_http_status(:unauthorized)
  end
end
