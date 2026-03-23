module Symphony
  class PollJob < ApplicationJob
    queue_as :symphony

    def perform
      Symphony.orchestrator&.tick
      Symphony::ManagedWorkflow.where(status: "active").pluck(:id).each do |workflow_id|
        Symphony::WorkflowTriggerScheduler.enqueue(workflow_id: workflow_id, source: "poll")
      end
    end
  end
end
