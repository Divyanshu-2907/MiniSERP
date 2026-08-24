# frozen_string_literal: true

require "rails_helper"

RSpec.describe "service metadata", type: :request do
  it "describes the service at the root path without a key" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(json_body).to include("service" => "miniserp", "status" => "ok")
    expect(json_body["endpoints"]).to include("search")
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
