Rails.application.routes.draw do
  # Liveness probe (unauthenticated).
  get "up" => "rails/health#show", as: :rails_health_check

  # Service description (unauthenticated).
  root to: "meta#show"

  namespace :api do
    namespace :v1 do
      get "search", to: "searches#show"
      resources :engines, only: :index
    end
  end

  # Unversioned convenience alias for the primary endpoint, so the documented
  # `GET /search?q=...` works without pinning callers to a version prefix.
  get "search", to: "api/v1/searches#show", as: :search
end
