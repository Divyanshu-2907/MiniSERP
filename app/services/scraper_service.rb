# frozen_string_literal: true

# Orchestrates a single search: cache lookup -> fetch -> block detection ->
# parse -> cache write.
#
# It owns no HTTP and no HTML knowledge of its own; the transport
# (Scraper::Client / Scraper::FixtureClient) and the engine parser
# (Scraper::Engines::*) are injected, which is what makes the specs able to
# drive every branch without a network.
class ScraperService
  Result = Struct.new(
    :query, :engine, :results, :scraped_at, :cached, :cache_age_seconds,
    keyword_init: true
  ) do
    def count      = results.length
    def empty?     = results.empty?
    def cached?    = !!cached
  end

  def self.call(**kwargs) = new(**kwargs).call

  def initialize(query:, engine: nil, refresh: false, client: nil, ttl_hours: nil, limit: nil, logger: nil)
    @query     = query.to_s.squish
    @engine    = Scraper::Registry.fetch(engine)
    @refresh   = ActiveModel::Type::Boolean.new.cast(refresh) || false
    @client    = client || self.class.default_client
    @ttl_hours = ttl_hours || MiniSerp.config.cache_ttl_hours
    @limit     = limit || MiniSerp.config.max_results
    @logger    = logger || Rails.logger
  end

  # The transport is chosen by configuration, not by the caller, so that
  # "never hit Google by accident" is a single switch (MINISERP_SOURCE).
  def self.default_client
    MiniSerp.config.live? ? Scraper::Client.new : Scraper::FixtureClient.new
  end

  def call
    raise Scraper::Errors::InvalidQuery, "the q parameter is required" if @query.blank?

    cached = cached_result unless @refresh
    return from_cache(cached) if cached

    scrape
  end

  private

  def cached_result
    SearchResult.fresh(query: @query, engine: @engine.key, ttl_hours: @ttl_hours)
  rescue Mongo::Error => e
    # A cache that is down should slow us down, not take the API with it.
    @logger&.error("[scraper] cache read failed: #{e.class}: #{e.message}")
    nil
  end

  def from_cache(record)
    @logger&.info("[scraper] cache hit for #{@engine.key}:#{@query.inspect}")

    Result.new(
      query: record.query,
      engine: record.engine,
      results: normalize(record.results),
      scraped_at: record.scraped_at,
      cached: true,
      cache_age_seconds: record.age_seconds
    )
  end

  def scrape
    response = @client.get(@engine.search_url(@query, limit: @limit))

    if @engine.blocked?(response)
      @logger&.warn("[scraper] blocked by #{@engine.key} for #{@query.inspect}")
      raise Scraper::Errors::Blocked,
            "#{@engine.key} served an anti-bot page instead of results"
    end

    results    = @engine.parse(response.document, limit: @limit)
    scraped_at = Time.current

    persist(results, scraped_at)

    Result.new(
      query: @query,
      engine: @engine.key,
      results: normalize(results),
      scraped_at: scraped_at,
      cached: false,
      cache_age_seconds: 0
    )
  end

  # Empty result sets are cached too -- re-scraping a query that genuinely has
  # no results just burns requests against the engine.
  def persist(results, scraped_at)
    return unless MiniSerp.config.caching_enabled?

    SearchResult.create!(
      query: @query,
      engine: @engine.key,
      results: results.map { |row| row.transform_keys(&:to_s) },
      scraped_at: scraped_at
    )
  rescue Mongo::Error, Mongoid::Errors::MongoidError => e
    @logger&.error("[scraper] cache write failed: #{e.class}: #{e.message}")
  end

  # Mongo hands back string keys; freshly parsed rows use symbols. Callers
  # should not be able to tell a cache hit from a live scrape by key type.
  def normalize(rows)
    Array(rows).map do |row|
      row = row.respond_to?(:to_h) ? row.to_h : row
      row.symbolize_keys.slice(:position, :title, :link, :snippet)
    end
  end
end
