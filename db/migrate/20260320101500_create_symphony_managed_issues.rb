class CreateSymphonyManagedIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :symphony_managed_issues do |t|
      t.references :managed_workflow, null: false, foreign_key: { to_table: :symphony_managed_workflows }
      t.string :identifier, null: false
      t.string :title, null: false
      t.text :description
      t.string :priority
      t.string :state
      t.json :labels
      t.json :blocked_by
      t.json :metadata

      t.timestamps
    end
  end
end
