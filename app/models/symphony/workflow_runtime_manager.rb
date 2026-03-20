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
    end
  end
end
