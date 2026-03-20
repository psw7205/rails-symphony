class CreateSymphonyAgentConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :symphony_agent_connections do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.json :config

      t.timestamps
    end
  end
end
