module Symphony
  class ProjectsController < ApplicationController
    def index
      @projects = ManagedProject.order(:name)
    end

    def new
      @project = ManagedProject.new(status: "active")
    end

    def create
      @project = ManagedProject.new(project_params)
      if @project.save
        redirect_to "/projects/#{@project.id}"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @project = ManagedProject.includes(:managed_workflows).find(params[:id])
      @workflow_rows = @project.managed_workflows.order(:name).map do |workflow|
        { managed_workflow: workflow, snapshot: WorkflowRuntimeManager.snapshot(workflow.id) }
      end
    end

    private
      def project_params
        params.require(:managed_project).permit(:name, :slug, :status, :description)
      end
  end
end
