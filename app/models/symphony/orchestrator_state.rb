module Symphony
  class OrchestratorState < ApplicationRecord
    self.table_name = "symphony_orchestrator_states"

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow", optional: true
    belongs_to :last_workflow_trigger_event, class_name: "Symphony::WorkflowTriggerEvent", optional: true
    validates :managed_workflow_id, uniqueness: true, allow_nil: true

    def self.for_workflow!(managed_workflow_id)
      find_or_create_by!(managed_workflow_id: managed_workflow_id)
    end

    # Legacy file-mode singleton accessor. Managed mode should use for_workflow!.
    def self.current
      find_or_create_by!(managed_workflow_id: nil)
    end

    def self.record_trigger!(workflow_id:, source:, requested_at:, trigger_event:)
      state = for_workflow!(workflow_id)
      state.update!(
        last_trigger_source: source,
        last_triggered_at: requested_at,
        last_workflow_trigger_event: trigger_event
      )
    end

    def self.record_tick_start!(workflow_id:, source:, trigger_event:, started_at:)
      state = for_workflow!(workflow_id)
      state.update!(
        last_trigger_source: source,
        last_triggered_at: trigger_event&.requested_at || started_at,
        last_tick_started_at: started_at,
        last_tick_status: "running",
        last_tick_error: nil,
        last_workflow_trigger_event: trigger_event
      )
    end

    def self.record_tick_finish!(workflow_id:, source:, trigger_event:, finished_at:, status:, error: nil)
      state = for_workflow!(workflow_id)
      state.update!(
        last_trigger_source: source,
        last_triggered_at: trigger_event&.requested_at || finished_at,
        last_tick_finished_at: finished_at,
        last_tick_status: status,
        last_tick_error: error,
        last_workflow_trigger_event: trigger_event
      )
    end
  end
end
