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

      def create_workflow
        workflow = Symphony::ManagedWorkflow.find_by(id: params[:workflow_id])
        unless workflow
          return render json: { error: { code: "workflow_not_found", message: "Workflow not found" } }, status: 404
        end

        if workflow.status != "active"
          return render json: { error: { code: "workflow_inactive", message: "Workflow is inactive" } }, status: 409
        end

        result = Symphony::WorkflowTriggerScheduler.enqueue(
          workflow_id: workflow.id,
          source: "manual_refresh"
        )
        render json: result, status: 202
      end
    end
  end
end
