module Symphony
  class WorkflowRuntimeManager
    @contexts = {}
    @mutex = Mutex.new

    class << self
      def fetch(managed_workflow_id)
        @mutex.synchronize do
          @contexts[managed_workflow_id] ||= WorkflowRuntimeFactory.build(managed_workflow_id)
        end
      end

      def refresh(managed_workflow_id)
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
    end
  end
end
