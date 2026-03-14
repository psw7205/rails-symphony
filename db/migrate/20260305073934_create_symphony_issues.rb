class CreateSymphonyIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :symphony_issues, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :identifier, null: false
      t.string :title
      t.text :description
      t.integer :priority
      t.string :state
      t.string :branch_name
      t.string :url
      t.json :labels, default: []
      t.json :blocked_by, default: []
      t.timestamps
    end

    add_index :symphony_issues, :identifier, unique: true
    add_index :symphony_issues, :state

    create_table :symphony_run_attempts do |t|
      t.string :issue_id, null: false
      t.integer :attempt, null: false
      t.string :workspace_path
      t.string :status, default: "pending"
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :symphony_run_attempts, :issue_id
    add_index :symphony_run_attempts, %i[issue_id attempt]

    create_table :symphony_agent_sessions do |t|
      t.references :run_attempt, null: false, foreign_key: { to_table: :symphony_run_attempts }
      t.string :session_id
      t.string :thread_id
      t.string :turn_id
      t.integer :codex_app_server_pid
      t.string :last_codex_event
      t.datetime :last_codex_timestamp
      t.text :last_codex_message
      t.integer :codex_input_tokens, default: 0
      t.integer :codex_output_tokens, default: 0
      t.integer :codex_total_tokens, default: 0
      t.integer :turn_count, default: 0
      t.timestamps
    end

    create_table :symphony_retry_entries do |t|
      t.string :issue_id, null: false
      t.string :identifier, null: false
      t.integer :attempt, null: false
      t.datetime :due_at
      t.text :error
      t.timestamps
    end

    add_index :symphony_retry_entries, :issue_id, unique: true

    create_table :symphony_orchestrator_states do |t|
      t.integer :codex_total_input_tokens, default: 0
      t.integer :codex_total_output_tokens, default: 0
      t.integer :codex_total_tokens, default: 0
      t.float :codex_total_seconds_running, default: 0.0
      t.json :codex_rate_limits
      t.timestamps
    end
  end
end
