module Symphony
  class WorkflowOperationsController < ApplicationController
    def pause
      workflow = ManagedWorkflow.find(params[:workflow_id])
      workflow.update!(status: "inactive") if workflow.status == "active"
      redirect_to "/workflows/#{workflow.id}"
    end

    def resume
      workflow = ManagedWorkflow.find(params[:workflow_id])
      if workflow.status == "inactive"
        workflow.update!(status: "active")
        WorkflowTriggerScheduler.enqueue(
          workflow_id: workflow.id,
          source: "manual_refresh",
          metadata: { operation: "resume" }
        )
      end

      redirect_to "/workflows/#{workflow.id}"
    end

    def refresh_now
      workflow = ManagedWorkflow.find(params[:workflow_id])
      WorkflowTriggerScheduler.enqueue(workflow_id: workflow.id, source: "manual_refresh") if workflow.status == "active"
      redirect_to "/workflows/#{workflow.id}"
    end
  end
end
