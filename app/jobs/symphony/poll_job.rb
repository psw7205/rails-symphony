module Symphony
  class PollJob < ApplicationJob
    queue_as :symphony

    def perform
      Symphony.orchestrator&.tick
      Symphony::ManagedWorkflow.where(status: "active").pluck(:id).each do |workflow_id|
        Symphony::WorkflowPollJob.perform_later(workflow_id: workflow_id)
      end
    end
  end
end
