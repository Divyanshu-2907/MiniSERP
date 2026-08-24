# frozen_string_literal: true

module Scraper
  # Every failure the scraping stack can produce, each carrying the machine
  # readable code and HTTP status the API should surface for it. Controllers
  # rescue Scraper::Errors::Base and never have to map exceptions by hand.
  module Errors
    class Base < StandardError
      def code        = :scrape_failed
      def http_status = :bad_gateway

      def as_json(*)
        { error: code.to_s, message: message }
      end
    end

    # The engine served an "are you a robot?" interstitial instead of results.
    class Blocked < Base
      def code        = :blocked
      def http_status = :forbidden
    end

    # Connection/read timeout that survived the retry.
    class Timeout < Base
      def code        = :timeout
      def http_status = :gateway_timeout
    end

    # Non-2xx response, connection reset, DNS failure, ...
    class RequestFailed < Base
      def code        = :request_failed
      def http_status = :bad_gateway
    end

    # ?engine= names something we have no parser for.
    class UnsupportedEngine < Base
      def code        = :unsupported_engine
      def http_status = :bad_request
    end

    # Missing/blank ?q=.
    class InvalidQuery < Base
      def code        = :invalid_query
      def http_status = :bad_request
    end

    # 200 OK, no CAPTCHA markers, but nothing we recognise as a result block --
    # usually the signature of a layout change rather than a genuinely empty
    # result page (which the engine reports explicitly).
    class ParseFailed < Base
      def code        = :parse_failed
      def http_status = :bad_gateway
    end
  end
end
