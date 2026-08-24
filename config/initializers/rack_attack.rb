# frozen_string_literal: true

# Per-API-key rate limiting.
#
# The counter store is an in-process MemoryStore, which is correct for a single
# Puma process and for the test suite. A multi-process or multi-dyno deploy
# needs a shared store -- point this at Redis (ActiveSupport::Cache::RedisCacheStore)
# and the rest of this file is unchanged.
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Throttling is off in the test environment by default; the rate-limit spec
# turns it on for the examples that assert on it.
Rack::Attack.enabled = !Rails.env.test?

Rack::Attack.throttle(
  "search/api_key",
  limit: ->(_request) { MiniSerp.config.rate_limit_per_minute },
  period: 60.seconds
) do |request|
  next unless request.path == "/search" || request.path.start_with?("/api/")

  # Key on the API key so one noisy client cannot spend another's budget.
  # Unauthenticated callers fall back to IP, which keeps a key-guessing loop
  # from being unlimited.
  request.get_header("HTTP_X_API_KEY").presence || "ip:#{request.ip}"
end

Rack::Attack.throttled_responder = lambda do |request|
  match  = request.env["rack.attack.match_data"] || {}
  period = match[:period].to_i
  limit  = match[:limit].to_i
  retry_after = period.positive? ? (period - (Time.now.to_i % period)) : 60

  body = {
    error: "rate_limit_exceeded",
    message: "too many requests: limit is #{limit} per #{period} seconds",
    retry_after: retry_after
  }.to_json

  headers = {
    "Content-Type" => "application/json",
    "Retry-After" => retry_after.to_s,
    "RateLimit-Limit" => limit.to_s,
    "RateLimit-Remaining" => "0"
  }

  [ 429, headers, [ body ] ]
end

ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.warn("[rack-attack] throttled #{request.request_method} #{request.path}")
end
