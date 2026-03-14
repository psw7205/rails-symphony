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

ActiveRecord::Schema[8.1].define(version: 2026_03_05_073934) do
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
    t.integer "priority"
    t.string "state"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["identifier"], name: "index_symphony_issues_on_identifier", unique: true
    t.index ["state"], name: "index_symphony_issues_on_state"
  end

  create_table "symphony_orchestrator_states", force: :cascade do |t|
    t.json "codex_rate_limits"
    t.integer "codex_total_input_tokens", default: 0
    t.integer "codex_total_output_tokens", default: 0
    t.float "codex_total_seconds_running", default: 0.0
    t.integer "codex_total_tokens", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "symphony_retry_entries", force: :cascade do |t|
    t.integer "attempt", null: false
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.text "error"
    t.string "identifier", null: false
    t.string "issue_id", null: false
    t.datetime "updated_at", null: false
    t.index ["issue_id"], name: "index_symphony_retry_entries_on_issue_id", unique: true
  end

  create_table "symphony_run_attempts", force: :cascade do |t|
    t.integer "attempt", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.string "issue_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.string "workspace_path"
    t.index ["issue_id", "attempt"], name: "index_symphony_run_attempts_on_issue_id_and_attempt"
    t.index ["issue_id"], name: "index_symphony_run_attempts_on_issue_id"
  end

  add_foreign_key "symphony_agent_sessions", "symphony_run_attempts", column: "run_attempt_id"
end
