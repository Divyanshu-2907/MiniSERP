# frozen_string_literal: true

module Scraper
  # Live HTTP transport.
  #
  # Retry policy: one retry, after a short backoff, and only for failures that
  # are plausibly transient (timeouts, connection resets, 5xx, 429). A 403 or a
  # CAPTCHA page is not retried -- hammering an engine that just blocked you is
  # how a soft block becomes a hard one.
  class Client
    RETRYABLE_EXCEPTIONS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      SocketError,
      HTTParty::Error
    ].freeze

    RETRYABLE_STATUSES = [ 429, 500, 502, 503, 504 ].freeze

    def initialize(timeout: nil, user_agent: nil, backoff: nil, max_attempts: 2, logger: nil)
      @timeout      = timeout      || MiniSerp.config.http_timeout
      @user_agent   = user_agent   || MiniSerp.config.user_agent
      @backoff      = backoff      || MiniSerp.config.http_retry_backoff
      @max_attempts = max_attempts
      @logger       = logger || Rails.logger
    end

    def get(url, headers: {})
      attempt = 0

      begin
        attempt += 1
        response = perform(url, headers)

        if RETRYABLE_STATUSES.include?(response.code) && attempt < @max_attempts
          @logger&.warn("[scraper] HTTP #{response.code} from #{url}, retrying")
          sleep_backoff(attempt)
          raise Retry
        end

        unless response.code.between?(200, 299)
          raise Errors::RequestFailed, "search engine responded with HTTP #{response.code}"
        end

        Response.new(
          body: response.body,
          status: response.code,
          url: url,
          headers: response.headers.to_h
        )
      rescue Retry
        retry
      rescue *RETRYABLE_EXCEPTIONS => e
        if attempt < @max_attempts
          @logger&.warn("[scraper] #{e.class}: #{e.message}, retrying")
          sleep_backoff(attempt)
          retry
        end

        raise translate(e)
      end
    end

    private

    # Internal signal used to funnel retryable *status codes* through the same
    # path as retryable exceptions.
    Retry = Class.new(StandardError)
    private_constant :Retry

    def perform(url, headers)
      HTTParty.get(
        url,
        headers: default_headers.merge(headers),
        timeout: @timeout,
        follow_redirects: true
      )
    end

    def default_headers
      {
        "User-Agent" => @user_agent,
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9"
      }
    end

    def sleep_backoff(attempt)
      delay = @backoff * attempt
      sleep(delay) if delay.positive?
    end

    def translate(error)
      case error
      when Net::OpenTimeout, Net::ReadTimeout, HTTParty::Error
        if error.is_a?(HTTParty::Error) && !error.message.match?(/timeout/i)
          Errors::RequestFailed.new("request failed: #{error.message}")
        else
          Errors::Timeout.new("search engine did not respond in time")
        end
      else
        Errors::RequestFailed.new("request failed: #{error.class}: #{error.message}")
      end
    end
  end
end
