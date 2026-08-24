# frozen_string_literal: true

module Scraper
  # Maps the ?engine= parameter to a parser instance.
  class Registry
    DEFAULT = "google"

    ENGINES = {
      "google" => Engines::Google
    }.freeze

    class << self
      def fetch(name)
        key = normalize(name)
        klass = ENGINES[key]

        if klass.nil?
          raise Errors::UnsupportedEngine,
                "unsupported engine #{key.inspect}; supported: #{supported.join(', ')}"
        end

        klass.new
      end

      def supported = ENGINES.keys

      def normalize(name)
        value = name.to_s.strip.downcase
        value.presence || DEFAULT
      end
    end
  end
end
