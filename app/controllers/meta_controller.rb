# frozen_string_literal: true

# Unauthenticated service description served at the root path.
class MetaController < ApplicationController
  def show
    render json: {
      service: "miniserp",
      status: "ok",
      documentation: "https://github.com/your-handle/miniserp#readme",
      auth: { header: ApiKeyAuthentication::HEADER },
      endpoints: {
        search: "/search?q={query}&engine=google",
        search_versioned: "/api/v1/search?q={query}&engine=google",
        engines: "/api/v1/engines",
        health: "/up"
      }
    }
  end
end
