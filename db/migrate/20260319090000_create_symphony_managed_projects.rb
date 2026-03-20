class CreateSymphonyManagedProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :symphony_managed_projects do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false
      t.text :description

      t.timestamps
    end

    add_index :symphony_managed_projects, :slug, unique: true
  end
end
