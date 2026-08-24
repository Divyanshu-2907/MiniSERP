# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Client do
  subject(:client) { described_class.new(backoff: 0) }

  let(:url) { "https://www.google.com/search?q=ruby" }

  it "returns a Scraper::Response on success" do
    stub_request(:get, url).to_return(status: 200, body: "<html>ok</html>")

    response = client.get(url)

    expect(response).to be_success
    expect(response.body).to eq("<html>ok</html>")
    expect(response.url).to eq(url)
  end

  it "sends a browser-like User-Agent" do
    stub = stub_request(:get, url)
      .with(headers: { "User-Agent" => MiniSerp.config.user_agent })
      .to_return(status: 200, body: "ok")

    client.get(url)

    expect(stub).to have_been_requested
  end

  describe "retry policy" do
    it "retries once after a timeout and succeeds" do
      stub_request(:get, url).to_timeout.then.to_return(status: 200, body: "recovered")

      expect(client.get(url).body).to eq("recovered")
      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "gives up with a Timeout error after the retry also times out" do
      stub_request(:get, url).to_timeout

      expect { client.get(url) }.to raise_error(Scraper::Errors::Timeout)
      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "retries a 503 and succeeds" do
      stub_request(:get, url).to_return({ status: 503 }, { status: 200, body: "recovered" })

      expect(client.get(url).body).to eq("recovered")
      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "raises RequestFailed when the retry is also a 5xx" do
      stub_request(:get, url).to_return(status: 500)

      expect { client.get(url) }.to raise_error(Scraper::Errors::RequestFailed, /HTTP 500/)
      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "does not retry a 404, which will not fix itself" do
      stub_request(:get, url).to_return(status: 404)

      expect { client.get(url) }.to raise_error(Scraper::Errors::RequestFailed, /HTTP 404/)
      expect(a_request(:get, url)).to have_been_made.once
    end

    it "translates a connection reset into RequestFailed" do
      stub_request(:get, url).to_raise(Errno::ECONNRESET)

      expect { client.get(url) }.to raise_error(Scraper::Errors::RequestFailed)
    end
  end

  describe "backoff" do
    it "sleeps between attempts" do
      stub_request(:get, url).to_timeout.then.to_return(status: 200, body: "ok")
      slow = described_class.new(backoff: 0.25)
      allow(slow).to receive(:sleep)

      slow.get(url)

      expect(slow).to have_received(:sleep).with(0.25).once
    end
  end
end
