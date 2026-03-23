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

    def edit
      @project = ManagedProject.find(params[:id])
    end

    def update
      @project = ManagedProject.find(params[:id])
      if @project.update(project_params)
        redirect_to "/projects/#{@project.id}"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @project = ManagedProject.find(params[:id])
      @project.destroy!
      redirect_to "/projects"
    end

    def show
      @project = ManagedProject.includes(managed_workflows: :tracker_connection).find(params[:id])
      @workflow_rows = @project.managed_workflows.order(:name).map do |workflow|
        snapshot = WorkflowRuntimeManager.snapshot(workflow.id)
        {
          managed_workflow: workflow,
          snapshot: snapshot,
          health: workflow_health(snapshot)
        }
      end
    end

    private
      def project_params
        params.require(:managed_project).permit(:name, :slug, :status, :description)
      end

      def workflow_health(snapshot)
        return "retrying" if snapshot[:counts][:retrying].positive?
        return "running" if snapshot[:counts][:running].positive?

        "idle"
      end
  end
end
