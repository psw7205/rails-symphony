module Symphony
  class WorkflowPollJob < ApplicationJob
    queue_as :symphony

    def perform(workflow_id:)
      Symphony::WorkflowRuntimeManager.fetch(workflow_id).orchestrator.tick
    end
  end
end
