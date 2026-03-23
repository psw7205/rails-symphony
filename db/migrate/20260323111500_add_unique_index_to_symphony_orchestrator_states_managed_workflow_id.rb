class AddUniqueIndexToSymphonyOrchestratorStatesManagedWorkflowId < ActiveRecord::Migration[8.1]
  def change
    add_index :symphony_orchestrator_states,
              :managed_workflow_id,
              unique: true,
              where: "managed_workflow_id IS NOT NULL",
              name: "idx_symphony_orchestrator_states_on_managed_workflow_id_unique"
  end
end
