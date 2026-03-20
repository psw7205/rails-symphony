module Api
  module V1
    class StatesController < ApplicationController
      skip_forgery_protection

      def show
        if Symphony.orchestrator
          render json: Symphony.orchestrator.snapshot
        else
          render json: { error: { code: "orchestrator_unavailable", message: "Orchestrator is not running" } }, status: 503
        end
      end

      def show_workflow
        render json: Symphony::WorkflowRuntimeManager.snapshot(params[:workflow_id])
      end
    end
  end
end
