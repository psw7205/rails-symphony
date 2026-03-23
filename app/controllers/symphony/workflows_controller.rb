module Symphony
  class WorkflowsController < ApplicationController
    def new
      @workflow = ManagedWorkflow.new(status: "active")
      load_form_dependencies
    end

    def create
      @workflow = ManagedWorkflow.new(workflow_params)
      @workflow.runtime_config_json = raw_runtime_config_json

      if assign_parsed_runtime_config(@workflow) && @workflow.save
        WorkflowRuntimeManager.refresh(@workflow.id)
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
      @workflow.runtime_config_json = raw_runtime_config_json

      if assign_parsed_runtime_config(@workflow) && @workflow.save
        WorkflowRuntimeManager.refresh(@workflow.id)
        redirect_to "/workflows/#{@workflow.id}"
      else
        load_form_dependencies
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @workflow = ManagedWorkflow.find(params[:id])
      project_id = @workflow.managed_project_id
      @workflow.destroy!
      redirect_to "/projects/#{project_id}"
    end

    def show
      @workflow = ManagedWorkflow.includes(:managed_project, :tracker_connection, :agent_connection).find(params[:id])
      @snapshot = WorkflowRuntimeManager.snapshot(@workflow.id)
      @recent_attempts = RunAttempt.where(managed_workflow_id: @workflow.id).order(created_at: :desc).limit(20)
      @orchestrator_state = OrchestratorState.includes(:last_workflow_trigger_event).find_by(managed_workflow_id: @workflow.id)
      @trigger_events = WorkflowTriggerEvent.where(managed_workflow_id: @workflow.id).order(requested_at: :desc).limit(10)
      @capabilities = WorkflowRuntimeManager.fetch(@workflow.id).tracker.capabilities
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

      def raw_runtime_config_json
        params.dig(:managed_workflow, :runtime_config_json).to_s
      end

      def assign_parsed_runtime_config(workflow)
        return workflow.runtime_config = {} if raw_runtime_config_json.blank?

        workflow.runtime_config = JSON.parse(raw_runtime_config_json)
        true
      rescue JSON::ParserError
        workflow.errors.add(:runtime_config_json, "is invalid JSON")
        false
      end

      def load_form_dependencies
        @projects = ManagedProject.order(:name)
        @tracker_connections = TrackerConnection.order(:name)
        @agent_connections = AgentConnection.order(:name)
      end
  end
end
