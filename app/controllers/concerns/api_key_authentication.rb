# frozen_string_literal: true

# Validates the X-API-Key header against MINISERP_API_KEYS.
module ApiKeyAuthentication
  extend ActiveSupport::Concern

  HEADER = "X-API-Key"

  included do
    before_action :authenticate_api_key!
  end

  private

  def current_api_key
    @current_api_key
  end

  def authenticate_api_key!
    presented = request.headers[HEADER].to_s.strip

    if presented.blank?
      return render_unauthorized("missing #{HEADER} header")
    end

    unless MiniSerp.config.valid_api_key?(presented)
      return render_unauthorized("invalid API key")
    end

    @current_api_key = presented
  end

  def render_unauthorized(message)
    render json: { error: "unauthorized", message: message }, status: :unauthorized
  end
end
