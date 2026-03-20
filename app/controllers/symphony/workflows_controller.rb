module Symphony
  class WorkflowsController < ApplicationController
    def show
      @workflow = ManagedWorkflow.includes(:managed_project, :tracker_connection, :agent_connection).find(params[:id])
      @snapshot = WorkflowRuntimeManager.snapshot(@workflow.id)
      @recent_attempts = RunAttempt.where(managed_workflow_id: @workflow.id).order(created_at: :desc).limit(20)
    end
  end
end
