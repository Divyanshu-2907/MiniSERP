# frozen_string_literal: true

module Api
  module V1
    # Every v1 endpoint is authenticated and rate limited.
    class BaseController < ApplicationController
      include ApiKeyAuthentication
    end
  end
end
