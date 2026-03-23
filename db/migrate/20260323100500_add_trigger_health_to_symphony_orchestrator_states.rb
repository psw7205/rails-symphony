class AddTriggerHealthToSymphonyOrchestratorStates < ActiveRecord::Migration[8.1]
  def change
    add_column :symphony_orchestrator_states, :last_trigger_source, :string
    add_column :symphony_orchestrator_states, :last_triggered_at, :datetime
    add_column :symphony_orchestrator_states, :last_tick_started_at, :datetime
    add_column :symphony_orchestrator_states, :last_tick_finished_at, :datetime
    add_column :symphony_orchestrator_states, :last_tick_status, :string
    add_column :symphony_orchestrator_states, :last_tick_error, :text
    add_reference :symphony_orchestrator_states,
                  :last_workflow_trigger_event,
                  foreign_key: { to_table: :symphony_workflow_trigger_events }
  end
end
