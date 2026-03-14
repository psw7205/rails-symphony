module Api
  module V1
    class RefreshesController < ApplicationController
      skip_forgery_protection

      def create
        if Symphony.orchestrator
          result = Symphony.orchestrator.request_refresh
          render json: result, status: 202
        else
          render json: { error: { code: "orchestrator_unavailable", message: "Orchestrator is unavailable" } }, status: 503
        end
      end
    end
  end
end
