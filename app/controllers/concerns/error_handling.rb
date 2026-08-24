# frozen_string_literal: true

# Turns exceptions from the scraping stack into the API's error envelope, so
# controller actions stay free of rescue blocks.
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from Scraper::Errors::Base, with: :render_scraper_error
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
    rescue_from StandardError, with: :render_unexpected_error unless Rails.env.local?
  end

  private

  def render_scraper_error(error)
    logger.warn("[api] #{error.class}: #{error.message}")

    render json: { error: error.code.to_s, message: error.message },
           status: error.http_status
  end

  def render_parameter_missing(error)
    render json: { error: "invalid_request", message: error.message },
           status: :bad_request
  end

  def render_unexpected_error(error)
    logger.error("[api] unhandled #{error.class}: #{error.message}")
    logger.error(error.backtrace&.first(10)&.join("\n"))

    render json: { error: "internal_error", message: "something went wrong on our side" },
           status: :internal_server_error
  end
end
