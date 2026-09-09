Rails.application.routes.draw do
  # Liveness probe (unauthenticated).
  get "up" => "rails/health#show", as: :rails_health_check

  # Service description as JSON (unauthenticated).
  #
  # public/index.html is served at "/" by ActionDispatch::Static, which runs
  # ahead of the router -- so the browser gets the demo page and API clients
  # get this. The root route stays as the fallback if that file is removed.
  get "/api/v1", to: "meta#show", as: :service_info
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
