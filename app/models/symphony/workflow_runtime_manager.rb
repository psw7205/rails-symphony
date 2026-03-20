module Symphony
  class WorkflowRuntimeManager
    @contexts = {}
    @mutex = Mutex.new

    class << self
      def fetch(managed_workflow_id)
        managed_workflow_id = normalize_workflow_id(managed_workflow_id)
        @mutex.synchronize do
          @contexts[managed_workflow_id] ||= WorkflowRuntimeFactory.build(managed_workflow_id)
        end
      end

      def refresh(managed_workflow_id)
        managed_workflow_id = normalize_workflow_id(managed_workflow_id)
        @mutex.synchronize do
          @contexts[managed_workflow_id] = WorkflowRuntimeFactory.build(managed_workflow_id)
        end
      end

      def snapshot(managed_workflow_id)
        fetch(managed_workflow_id).orchestrator.snapshot
      end

      def global_snapshot
        ManagedWorkflow.where(status: "active").order(:id).map do |managed_workflow|
          context = fetch(managed_workflow.id)
          { managed_workflow: context.managed_workflow, snapshot: context.orchestrator.snapshot }
        end
      end

      def clear!(managed_workflow_id = nil)
        @mutex.synchronize do
          if managed_workflow_id.nil?
            @contexts.clear
          else
            managed_workflow_id = normalize_workflow_id(managed_workflow_id)
            @contexts.delete(managed_workflow_id)
          end
        end
      end

      private
        def normalize_workflow_id(managed_workflow_id)
          managed_workflow_id.to_i
        end
    end
  end
end
