# frozen_string_literal: true

# Turns exceptions from the scraping stack into the API's error envelope, so
# controller actions stay free of rescue blocks.
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    # ORDER MATTERS. Rails matches rescue_from handlers in *reverse*
    # registration order -- the last matching handler registered wins. So the
    # broadest handler must be registered FIRST, or it swallows every specific
    # handler declared after it and turns deliberate 400/403s into 500s.
    rescue_from StandardError, with: :render_unexpected_error
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
    rescue_from Scraper::Errors::Base, with: :render_scraper_error
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

  # Registered in every environment -- so dev, test and production all exercise
  # the same handler chain -- but re-raised locally to keep full backtraces in
  # development and to let specs fail loudly on unexpected errors.
  def render_unexpected_error(error)
    raise error if Rails.env.local?

    logger.error("[api] unhandled #{error.class}: #{error.message}")
    logger.error(error.backtrace&.first(10)&.join("\n"))

    render json: { error: "internal_error", message: "something went wrong on our side" },
           status: :internal_server_error
  end
end
