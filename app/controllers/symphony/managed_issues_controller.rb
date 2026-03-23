module Symphony
  class ManagedIssuesController < ApplicationController
    def index
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issues = ManagedIssue.where(managed_workflow_id: @workflow.id).order(:id)
    end
  end
end
