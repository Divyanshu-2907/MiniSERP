# frozen_string_literal: true

module Scraper
  module Engines
    # Contract every engine parser implements. Adding an engine means adding a
    # subclass and one line in Scraper::Registry -- nothing above this layer
    # changes.
    class Base
      # Canonical name used by the ?engine= parameter.
      def self.key
        raise NotImplementedError, "#{name} must define .key"
      end

      def key = self.class.key

      # Absolute URL to fetch for this query.
      def search_url(_query, limit: nil)
        raise NotImplementedError, "#{self.class.name} must implement #search_url"
      end

      # True when the engine served an anti-bot interstitial instead of results.
      def blocked?(_response)
        false
      end

      # True when the engine explicitly says "nothing matched" -- distinct from
      # "we could not find any results in this HTML", which is a parse failure.
      def no_results?(_document)
        false
      end

      # => [{ position:, title:, link:, snippet: }, ...]
      def parse(_document, limit: nil)
        raise NotImplementedError, "#{self.class.name} must implement #parse"
      end

      private

      def squish(value)
        value.to_s.gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
