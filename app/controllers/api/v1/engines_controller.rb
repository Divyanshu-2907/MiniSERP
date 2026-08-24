# frozen_string_literal: true

module Api
  module V1
    class EnginesController < BaseController
      # GET /api/v1/engines
      def index
        render json: {
          default: Scraper::Registry::DEFAULT,
          engines: Scraper::Registry.supported,
          source: MiniSerp.config.source
        }
      end
    end
  end
end
