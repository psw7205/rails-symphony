class CreateSymphonyWorkflowTriggerEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :symphony_workflow_trigger_events do |t|
      t.references :managed_workflow, null: false, foreign_key: { to_table: :symphony_managed_workflows }
      t.string :source, null: false
      t.string :provider
      t.string :delivery_id
      t.string :status, null: false
      t.string :signature_state
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error
      t.json :metadata

      t.timestamps
    end

    add_index :symphony_workflow_trigger_events, :status
    add_index :symphony_workflow_trigger_events, [ :managed_workflow_id, :requested_at ], name: "idx_symphony_trigger_events_on_workflow_and_requested_at"
    add_index :symphony_workflow_trigger_events, [ :managed_workflow_id, :provider, :delivery_id ], name: "idx_symphony_trigger_events_on_workflow_provider_delivery"
  end
end
