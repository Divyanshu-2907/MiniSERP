# frozen_string_literal: true

# A single cached scrape: one query, on one engine, at one point in time.
#
# Documents are never updated in place -- every scrape inserts a new document,
# so the collection doubles as an audit trail of what the engine returned and
# when. Cache reads always take the newest fresh document.
class SearchResult
  include Mongoid::Document
  include Mongoid::Timestamps

  field :query,      type: String   # the query exactly as the caller sent it
  field :query_key,  type: String   # whitespace-normalised lookup key
  field :engine,     type: String
  field :results,    type: Array, default: -> { [] }
  field :scraped_at, type: Time

  index({ engine: 1, query_key: 1, scraped_at: -1 })

  validates :query, presence: true
  validates :engine, presence: true

  before_validation :assign_query_key

  # Whitespace is the only thing normalised away -- "ruby  on rails" and
  # "ruby on rails" are one cache entry, "Ruby on Rails" is a different one.
  def self.cache_key_for(query)
    query.to_s.squish
  end

  # Newest non-expired document for this query/engine pair, or nil.
  def self.fresh(query:, engine:, ttl_hours:)
    return nil unless ttl_hours.to_f.positive?

    where(query_key: cache_key_for(query), engine: engine.to_s)
      .gt(scraped_at: ttl_hours.to_f.hours.ago)
      .order_by(scraped_at: :desc)
      .first
  end

  def age_seconds
    return nil if scraped_at.blank?

    (Time.current - scraped_at).round
  end

  private

  def assign_query_key
    self.query_key = self.class.cache_key_for(query)
  end
end
