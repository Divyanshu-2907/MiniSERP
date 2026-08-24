# frozen_string_literal: true

module Api
  module V1
    class SearchesController < BaseController
      # GET /search?q=ruby+on+rails&engine=google
      # GET /api/v1/search?q=ruby+on+rails&engine=google
      def show
        result = ScraperService.call(
          query: search_params[:q],
          engine: search_params[:engine],
          refresh: search_params[:refresh]
        )

        render json: SearchResponseSerializer.new(result).as_json, status: :ok
      end

      private

      def search_params
        params.permit(:q, :engine, :refresh)
      end
    end
  end
end
