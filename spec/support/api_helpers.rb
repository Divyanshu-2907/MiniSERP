# frozen_string_literal: true

module ApiHelpers
  VALID_API_KEY = "test-key"

  def auth_headers(key = VALID_API_KEY)
    { ApiKeyAuthentication::HEADER => key }
  end

  def json_body
    JSON.parse(response.body)
  end
end
