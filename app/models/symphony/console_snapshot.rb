module Symphony
  class ConsoleSnapshot
    def self.build
      workflow_rows = WorkflowRuntimeManager.global_snapshot
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
        rate_limits: workflow_rows.each_with_object({}) do |row, limits|
          rate_limits = row[:snapshot][:rate_limits]
          next if rate_limits.blank?

          limits[row[:managed_workflow].slug] = rate_limits
        end,
        running: running_entries,
        retrying: retry_entries,
        recent_failures: retry_entries.select { |entry| entry[:error].present? },
        workflow_rows: workflow_rows
      }
    end
  end
end
