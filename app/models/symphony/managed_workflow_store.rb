module Symphony
  class ManagedWorkflowStore
    attr_reader :config, :prompt_template, :last_error, :managed_workflow_id

    def initialize(managed_workflow_id)
      @managed_workflow_id = managed_workflow_id
      @stamp = nil
      @config = {}
      @prompt_template = ""
      @last_error = nil
      @mutex = Mutex.new
      load!
    end

    def path = nil

    def service_config
      ServiceConfig.new(@config)
    end

    def reload_if_changed!
      @mutex.synchronize do
        workflow = fetch_workflow
        stamp = compute_stamp(workflow)
        do_reload(workflow, stamp) if stamp != @stamp
      end
    end

    def force_reload!
      @mutex.synchronize do
        workflow = fetch_workflow
        do_reload(workflow, compute_stamp(workflow))
      end
    end

    private
      def load!
        @mutex.synchronize do
          workflow = fetch_workflow
          do_reload(workflow, compute_stamp(workflow))
        end
      end

      def fetch_workflow
        ManagedWorkflow.includes(:tracker_connection, :agent_connection).find(@managed_workflow_id)
      end

      def do_reload(workflow, stamp)
        @config = WorkflowConfigBuilder.build(workflow)
        @prompt_template = workflow.prompt_template.to_s
        @stamp = stamp
        @last_error = nil
      rescue ActiveRecord::RecordNotFound
        @last_error = :managed_workflow_not_found
      end

      def compute_stamp(workflow)
        [
          workflow.updated_at&.to_f,
          workflow.tracker_connection&.updated_at&.to_f,
          workflow.agent_connection&.updated_at&.to_f
        ]
      end
  end
end
