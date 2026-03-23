module Symphony
  class ManagedIssuesController < ApplicationController
    def index
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issues = ManagedIssue.where(managed_workflow_id: @workflow.id).order(:id)
    end

    def new
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issue = ManagedIssue.new(managed_workflow: @workflow, state: "Todo")
    end

    def create
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issue = ManagedIssue.new(managed_issue_params.merge(managed_workflow: @workflow))
      if @managed_issue.save
        redirect_to "/workflows/#{@workflow.id}/issues"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issue = ManagedIssue.find(params[:id])
    end

    def update
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issue = ManagedIssue.find(params[:id])
      if @managed_issue.update(managed_issue_params)
        redirect_to "/workflows/#{@workflow.id}/issues"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @workflow = ManagedWorkflow.includes(:tracker_connection).find(params[:workflow_id])
      return head :not_found unless @workflow.tracker_connection.kind == "database"

      @managed_issue = ManagedIssue.find(params[:id])
      @managed_issue.destroy!
      redirect_to "/workflows/#{@workflow.id}/issues"
    end

    private
      def managed_issue_params
        params.require(:managed_issue).permit(:identifier, :title, :description, :priority, :state)
      end
  end
end
