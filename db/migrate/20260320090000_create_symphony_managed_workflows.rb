class CreateSymphonyManagedWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :symphony_managed_workflows do |t|
      t.references :managed_project, null: false, foreign_key: { to_table: :symphony_managed_projects }
      t.references :tracker_connection, null: false, foreign_key: { to_table: :symphony_tracker_connections }
      t.references :agent_connection, null: false, foreign_key: { to_table: :symphony_agent_connections }
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false
      t.text :prompt_template
      t.json :runtime_config

      t.timestamps
    end

    add_index :symphony_managed_workflows, :slug, unique: true
  end
end
