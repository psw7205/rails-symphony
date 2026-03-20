module Symphony
  class ConsoleSnapshot
    def self.build
      workflow_rows = WorkflowRuntimeManager.global_snapshot
      {
        project_count: ManagedProject.count,
        active_workflow_count: workflow_rows.size,
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
        running: workflow_rows.flat_map { |row| row[:snapshot][:running] },
        retrying: workflow_rows.flat_map { |row| row[:snapshot][:retrying] },
        workflow_rows: workflow_rows
      }
    end
  end
end
