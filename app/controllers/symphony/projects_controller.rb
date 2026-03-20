module Symphony
  class ProjectsController < ApplicationController
    def index
      @projects = ManagedProject.order(:name)
    end

    def show
      @project = ManagedProject.includes(:managed_workflows).find(params[:id])
      @workflow_rows = @project.managed_workflows.order(:name).map do |workflow|
        { managed_workflow: workflow, snapshot: WorkflowRuntimeManager.snapshot(workflow.id) }
      end
    end
  end
end
