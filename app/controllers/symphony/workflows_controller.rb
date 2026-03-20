module Symphony
  class WorkflowsController < ApplicationController
    def new
      @workflow = ManagedWorkflow.new(status: "active")
      load_form_dependencies
    end

    def create
      @workflow = ManagedWorkflow.new(workflow_params)
      @workflow.runtime_config = parsed_runtime_config

      if @workflow.save
        redirect_to "/workflows/#{@workflow.id}"
      else
        load_form_dependencies
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @workflow = ManagedWorkflow.find(params[:id])
      load_form_dependencies
    end

    def update
      @workflow = ManagedWorkflow.find(params[:id])
      @workflow.assign_attributes(workflow_params)
      @workflow.runtime_config = parsed_runtime_config

      if @workflow.save
        redirect_to "/workflows/#{@workflow.id}"
      else
        load_form_dependencies
        render :edit, status: :unprocessable_entity
      end
    end

    def show
      @workflow = ManagedWorkflow.includes(:managed_project, :tracker_connection, :agent_connection).find(params[:id])
      @snapshot = WorkflowRuntimeManager.snapshot(@workflow.id)
      @recent_attempts = RunAttempt.where(managed_workflow_id: @workflow.id).order(created_at: :desc).limit(20)
    end

    private
      def workflow_params
        params.require(:managed_workflow).permit(
          :managed_project_id,
          :tracker_connection_id,
          :agent_connection_id,
          :name,
          :slug,
          :status,
          :prompt_template
        )
      end

      def parsed_runtime_config
        raw = params.dig(:managed_workflow, :runtime_config_json)
        return {} if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def load_form_dependencies
        @projects = ManagedProject.order(:name)
        @tracker_connections = TrackerConnection.order(:name)
        @agent_connections = AgentConnection.order(:name)
      end
  end
end
