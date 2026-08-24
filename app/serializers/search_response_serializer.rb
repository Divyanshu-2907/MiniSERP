# frozen_string_literal: true

# Shapes a ScraperService::Result into the public JSON envelope.
class SearchResponseSerializer
  def initialize(result)
    @result = result
  end

  def as_json(*)
    {
      query: @result.query,
      engine: @result.engine,
      cached: @result.cached?,
      cache_age_seconds: @result.cache_age_seconds,
      scraped_at: @result.scraped_at&.utc&.iso8601,
      results_count: @result.count,
      no_results: @result.empty?,
      results: @result.results.map { |row| serialize_row(row) }
    }
  end

  private

  def serialize_row(row)
    {
      position: row[:position],
      title: row[:title],
      link: row[:link],
      snippet: row[:snippet]
    }
  end
end
