module Symphony
  class ConsoleSnapshot
    def self.build
      workflows = ManagedWorkflow.includes(:managed_project, :tracker_connection).order(:id).to_a
      active_rows = WorkflowRuntimeManager.global_snapshot.index_by { |row| row[:managed_workflow].id }
      states = OrchestratorState.includes(:last_workflow_trigger_event)
        .where(managed_workflow_id: workflows.map(&:id))
        .index_by(&:managed_workflow_id)

      workflow_rows = workflows.map do |workflow|
        runtime_row = active_rows[workflow.id]
        snapshot = runtime_row&.dig(:snapshot) || empty_snapshot
        state = states[workflow.id]
        last_event = state&.last_workflow_trigger_event

        {
          managed_workflow: workflow,
          snapshot: snapshot,
          trigger_summary: {
            source: state&.last_trigger_source,
            triggered_at: state&.last_triggered_at&.iso8601,
            tick_status: state&.last_tick_status,
            tick_error: state&.last_tick_error,
            event_status: last_event&.status
          }
        }
      end

      running_entries = workflow_rows.flat_map do |row|
        row[:snapshot][:running].map do |entry|
          entry.merge(managed_workflow_id: row[:managed_workflow].id)
        end
      end
      retry_entries = workflow_rows.flat_map do |row|
        row[:snapshot][:retrying].map do |entry|
          entry.merge(managed_workflow_id: row[:managed_workflow].id)
        end
      end

      {
        project_count: ManagedProject.count,
        active_workflow_count: workflows.count { |workflow| workflow.status == "active" },
        totals: {
          running: workflow_rows.sum { |row| row[:snapshot][:counts][:running] },
          retrying: workflow_rows.sum { |row| row[:snapshot][:counts][:retrying] }
        },
        codex_totals: {
          input_tokens: workflow_rows.sum { |row| row[:snapshot][:codex_totals][:input_tokens] || 0 },
          output_tokens: workflow_rows.sum { |row| row[:snapshot][:codex_totals][:output_tokens] || 0 },
          total_tokens: workflow_rows.sum { |row| row[:snapshot][:codex_totals][:total_tokens] || 0 },
          seconds_running: workflow_rows.sum { |row| row[:snapshot][:codex_totals][:seconds_running] || 0.0 }
        },
        rate_limits: workflow_rows.each_with_object({}) do |row, limits|
          rate_limits = row[:snapshot][:rate_limits]
          next if rate_limits.blank?

          limits[row[:managed_workflow].slug] = rate_limits
        end,
        running: running_entries,
        retrying: retry_entries,
        recent_failures: retry_entries.select { |entry| entry[:error].present? },
        recent_trigger_failures: WorkflowTriggerEvent.recent_failures
          .where(managed_workflow_id: workflows.map(&:id))
          .includes(:managed_workflow)
          .limit(20),
        workflow_rows: workflow_rows
      }
    end

    def self.empty_snapshot
      {
        counts: { running: 0, retrying: 0 },
        running: [],
        retrying: [],
        codex_totals: {
          input_tokens: 0,
          output_tokens: 0,
          total_tokens: 0,
          seconds_running: 0.0
        },
        rate_limits: nil
      }
    end
  end
end
