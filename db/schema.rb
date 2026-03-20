# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_20_104500) do
  create_table "symphony_agent_connections", force: :cascade do |t|
    t.json "config"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
  end

  create_table "symphony_agent_sessions", force: :cascade do |t|
    t.integer "codex_app_server_pid"
    t.integer "codex_input_tokens", default: 0
    t.integer "codex_output_tokens", default: 0
    t.integer "codex_total_tokens", default: 0
    t.datetime "created_at", null: false
    t.string "last_codex_event"
    t.text "last_codex_message"
    t.datetime "last_codex_timestamp"
    t.integer "run_attempt_id", null: false
    t.string "session_id"
    t.string "thread_id"
    t.integer "turn_count", default: 0
    t.string "turn_id"
    t.datetime "updated_at", null: false
    t.index ["run_attempt_id"], name: "index_symphony_agent_sessions_on_run_attempt_id"
  end

  create_table "symphony_issues", id: :string, force: :cascade do |t|
    t.json "blocked_by", default: []
    t.string "branch_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "identifier", null: false
    t.json "labels", default: []
    t.integer "managed_workflow_id"
    t.integer "priority"
    t.string "source_issue_id"
    t.string "state"
    t.string "title"
    t.string "tracker_kind"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["managed_workflow_id", "source_issue_id"], name: "index_symphony_issues_on_workflow_and_source_issue", unique: true
    t.index ["managed_workflow_id"], name: "index_symphony_issues_on_managed_workflow_id"
    t.index ["state"], name: "index_symphony_issues_on_state"
  end

  create_table "symphony_managed_issues", force: :cascade do |t|
    t.json "blocked_by"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "identifier", null: false
    t.json "labels"
    t.integer "managed_workflow_id", null: false
    t.json "metadata"
    t.string "priority"
    t.string "state"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["managed_workflow_id"], name: "index_symphony_managed_issues_on_managed_workflow_id"
  end

  create_table "symphony_managed_projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_symphony_managed_projects_on_slug", unique: true
  end

  create_table "symphony_managed_workflows", force: :cascade do |t|
    t.integer "agent_connection_id", null: false
    t.datetime "created_at", null: false
    t.integer "managed_project_id", null: false
    t.string "name", null: false
    t.text "prompt_template"
    t.json "runtime_config"
    t.string "slug", null: false
    t.string "status", null: false
    t.integer "tracker_connection_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_connection_id"], name: "index_symphony_managed_workflows_on_agent_connection_id"
    t.index ["managed_project_id"], name: "index_symphony_managed_workflows_on_managed_project_id"
    t.index ["slug"], name: "index_symphony_managed_workflows_on_slug", unique: true
    t.index ["tracker_connection_id"], name: "index_symphony_managed_workflows_on_tracker_connection_id"
  end

  create_table "symphony_orchestrator_states", force: :cascade do |t|
    t.json "codex_rate_limits"
    t.integer "codex_total_input_tokens", default: 0
    t.integer "codex_total_output_tokens", default: 0
    t.float "codex_total_seconds_running", default: 0.0
    t.integer "codex_total_tokens", default: 0
    t.datetime "created_at", null: false
    t.integer "managed_workflow_id"
    t.datetime "updated_at", null: false
    t.index ["managed_workflow_id"], name: "index_symphony_orchestrator_states_on_managed_workflow_id"
  end

  create_table "symphony_retry_entries", force: :cascade do |t|
    t.integer "attempt", null: false
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.text "error"
    t.string "identifier", null: false
    t.string "issue_id", null: false
    t.integer "managed_workflow_id"
    t.datetime "updated_at", null: false
    t.index ["issue_id"], name: "index_symphony_retry_entries_on_issue_id", unique: true
    t.index ["managed_workflow_id"], name: "index_symphony_retry_entries_on_managed_workflow_id"
  end

  create_table "symphony_run_attempts", force: :cascade do |t|
    t.integer "attempt", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.string "issue_id", null: false
    t.integer "managed_workflow_id"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.string "workspace_path"
    t.index ["issue_id", "attempt"], name: "index_symphony_run_attempts_on_issue_id_and_attempt"
    t.index ["issue_id"], name: "index_symphony_run_attempts_on_issue_id"
    t.index ["managed_workflow_id"], name: "index_symphony_run_attempts_on_managed_workflow_id"
  end

  create_table "symphony_tracker_connections", force: :cascade do |t|
    t.json "config"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "symphony_agent_sessions", "symphony_run_attempts", column: "run_attempt_id"
  add_foreign_key "symphony_issues", "symphony_managed_workflows", column: "managed_workflow_id"
  add_foreign_key "symphony_managed_issues", "symphony_managed_workflows", column: "managed_workflow_id"
  add_foreign_key "symphony_managed_workflows", "symphony_agent_connections", column: "agent_connection_id"
  add_foreign_key "symphony_managed_workflows", "symphony_managed_projects", column: "managed_project_id"
  add_foreign_key "symphony_managed_workflows", "symphony_tracker_connections", column: "tracker_connection_id"
  add_foreign_key "symphony_orchestrator_states", "symphony_managed_workflows", column: "managed_workflow_id"
  add_foreign_key "symphony_retry_entries", "symphony_managed_workflows", column: "managed_workflow_id"
  add_foreign_key "symphony_run_attempts", "symphony_managed_workflows", column: "managed_workflow_id"
end
