module Symphony
  class WorkflowPollJob < ApplicationJob
    queue_as :symphony

    def perform(workflow_id:, trigger_event_id: nil)
      trigger_event = Symphony::WorkflowTriggerEvent.find_by(id: trigger_event_id)
      started_at = Time.current

      if trigger_event
        trigger_event.update!(status: "running", started_at: started_at)
        Symphony::OrchestratorState.record_tick_start!(
          workflow_id: workflow_id,
          source: trigger_event.source,
          trigger_event: trigger_event,
          started_at: started_at
        )
      end

      result = Symphony::WorkflowRuntimeManager.fetch(workflow_id).orchestrator.tick
      if result.is_a?(Hash) && result[:ok] == false
        return record_failure!(workflow_id, trigger_event, result[:error])
      end

      return if trigger_event.blank?

      finished_at = Time.current
      trigger_event.update!(status: "succeeded", finished_at: finished_at, error: nil)
      Symphony::OrchestratorState.record_tick_finish!(
        workflow_id: workflow_id,
        source: trigger_event.source,
        trigger_event: trigger_event,
        finished_at: finished_at,
        status: "succeeded"
      )
    rescue => error
      record_failure!(workflow_id, trigger_event, error.message)
    end

    private
      def record_failure!(workflow_id, trigger_event, error)
        return if trigger_event.blank?

        finished_at = Time.current
        trigger_event.update!(status: "failed", finished_at: finished_at, error: error)
        Symphony::OrchestratorState.record_tick_finish!(
          workflow_id: workflow_id,
          source: trigger_event.source,
          trigger_event: trigger_event,
          finished_at: finished_at,
          status: "failed",
          error: error
        )
      end
  end
end
