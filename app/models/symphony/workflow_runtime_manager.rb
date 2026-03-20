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
    end
  end
end
