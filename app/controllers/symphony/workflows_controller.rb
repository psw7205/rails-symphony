module Symphony
  class WorkflowsController < ApplicationController
    def show
      @workflow = ManagedWorkflow.includes(:managed_project, :tracker_connection, :agent_connection).find(params[:id])
      @snapshot = WorkflowRuntimeManager.snapshot(@workflow.id)
    end
  end
end
