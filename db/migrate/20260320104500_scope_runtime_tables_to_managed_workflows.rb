class ScopeRuntimeTablesToManagedWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_reference :symphony_issues, :managed_workflow,
      foreign_key: { to_table: :symphony_managed_workflows }
    add_column :symphony_issues, :source_issue_id, :string
    add_column :symphony_issues, :tracker_kind, :string
    remove_index :symphony_issues, :identifier
    add_index :symphony_issues, [ :managed_workflow_id, :source_issue_id ],
      unique: true,
      name: "index_symphony_issues_on_workflow_and_source_issue"

    add_reference :symphony_run_attempts, :managed_workflow,
      foreign_key: { to_table: :symphony_managed_workflows }
    add_reference :symphony_retry_entries, :managed_workflow,
      foreign_key: { to_table: :symphony_managed_workflows }
    add_reference :symphony_orchestrator_states, :managed_workflow,
      foreign_key: { to_table: :symphony_managed_workflows }
  end
end
