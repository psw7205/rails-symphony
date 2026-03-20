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
        running: workflow_rows.flat_map { |row| row[:snapshot][:running] },
        retrying: workflow_rows.flat_map { |row| row[:snapshot][:retrying] },
        workflow_rows: workflow_rows
      }
    end
  end
end
