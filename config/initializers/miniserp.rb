# frozen_string_literal: true

# Central, ENV-driven configuration for MiniSERP.
#
# Defined in an initializer (rather than under app/) on purpose: these values
# are read during boot by the Rack::Attack initializer, and initializers must
# not depend on reloadable autoloaded constants.
module MiniSerp
  class Settings
    # Fixture mode is the default everywhere. Live scraping of a public search
    # engine is opt-in because it is against most engines' Terms of Service.
    SOURCES = %i[fixture live].freeze

    DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
                         "AppleWebKit/537.36 (KHTML, like Gecko) " \
                         "Chrome/126.0.0.0 Safari/537.36"

    def api_keys
      @api_keys ||= begin
        raw = ENV["MINISERP_API_KEYS"].to_s.split(",").map(&:strip).reject(&:empty?)
        raw.presence || default_api_keys
      end
    end

    # Constant-time comparison so a wrong key cannot be discovered by timing
    # the 401 response.
    def valid_api_key?(candidate)
      return false if candidate.blank?

      api_keys.any? do |known|
        ActiveSupport::SecurityUtils.secure_compare(known, candidate)
      end
    end

    def source
      @source ||= begin
        value = ENV.fetch("MINISERP_SOURCE", "fixture").to_s.downcase.to_sym
        SOURCES.include?(value) ? value : :fixture
      end
    end

    def live?    = source == :live
    def fixture? = source == :fixture

    def cache_ttl_hours = float_env("MINISERP_CACHE_TTL_HOURS", 6.0)
    def caching_enabled? = cache_ttl_hours.positive?

    def rate_limit_per_minute = int_env("MINISERP_RATE_LIMIT_PER_MINUTE", 30)
    def http_timeout          = float_env("MINISERP_HTTP_TIMEOUT", 8.0)
    def http_retry_backoff    = float_env("MINISERP_HTTP_RETRY_BACKOFF", 0.5)
    def max_results           = int_env("MINISERP_MAX_RESULTS", 20)

    def user_agent = ENV.fetch("MINISERP_USER_AGENT", DEFAULT_USER_AGENT)

    def fixture_dir
      Rails.root.join(ENV.fetch("MINISERP_FIXTURE_DIR", "spec/fixtures/html"))
    end

    def forced_fixture = ENV["MINISERP_FIXTURE"].presence

    # Test/console escape hatch: memoized readers above would otherwise pin the
    # first value they saw for the whole process.
    def reset!
      instance_variables.each { |ivar| instance_variable_set(ivar, nil) }
      self
    end

    private

    def default_api_keys
      Rails.env.local? ? %w[dev-key] : []
    end

    def int_env(name, default)
      value = ENV[name]
      value.presence ? Integer(value, exception: false) || default : default
    end

    def float_env(name, default)
      value = ENV[name]
      value.presence ? Float(value, exception: false) || default : default
    end
  end

  def self.config
    @config ||= Settings.new
  end
end
