require "test_helper"

class Symphony::OrchestratorPersistableTest < ActiveSupport::TestCase
  setup do
    @workflow_path = Rails.root.join("tmp", "test_persist_workflow.md")
    File.write(@workflow_path, <<~WORKFLOW)
      ---
      tracker:
        kind: memory
        active_states:
          - "In Progress"
          - "Todo"
        terminal_states:
          - "Done"
          - "Cancelled"
      agent:
        kind: codex
        model: o4-mini
        max_concurrent_agents: 3
      workspace:
        root: #{Rails.root.join("tmp", "test_persist_ws")}
      codex:
        stall_timeout_ms: 0
      ---
      Prompt: {{ issue.identifier }}
    WORKFLOW

    store = Symphony::WorkflowStore.new(@workflow_path.to_s)
    tracker = Symphony::Trackers::Memory.new
    workspace = Symphony::Workspace.new(root: Rails.root.join("tmp", "test_persist_ws").to_s)
    agent = Symphony::Agents::Base.new

    @dispatched = []
    @orchestrator = Symphony::Orchestrator.new(
      tracker: tracker,
      workspace: workspace,
      agent: agent,
      workflow_store: store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue, attempt: attempt } }
    )
    @tracker = tracker
  end

  teardown do
    FileUtils.rm_f(@workflow_path)
    FileUtils.rm_rf(Rails.root.join("tmp", "test_persist_ws"))
  end

  test "persist_dispatch creates PersistedIssue and RunAttempt" do
    issue = Symphony::Issue.new(
      id: "persist-1", identifier: "TEST-1", title: "Test issue",
      state: "In Progress"
    )

    @orchestrator.send(:persist_dispatch, issue, 1)

    pi = Symphony::PersistedIssue.find("persist-1")
    assert_equal "TEST-1", pi.identifier
    assert_equal "Test issue", pi.title
    assert_equal "In Progress", pi.state

    ra = pi.run_attempts.last
    assert_equal 1, ra.attempt
    assert_equal "running", ra.status
    assert_not_nil ra.started_at
  end

  test "persist_worker_exit updates RunAttempt status" do
    issue = Symphony::Issue.new(id: "persist-2", identifier: "TEST-2", title: "T", state: "In Progress")
    @orchestrator.send(:persist_dispatch, issue, 1)

    @orchestrator.send(:persist_worker_exit, "persist-2", status: "completed")

    ra = Symphony::RunAttempt.where(issue_id: "persist-2").last
    assert_equal "completed", ra.status
    assert_not_nil ra.finished_at
  end

  test "persist_worker_exit with error" do
    issue = Symphony::Issue.new(id: "persist-3", identifier: "TEST-3", title: "T", state: "In Progress")
    @orchestrator.send(:persist_dispatch, issue, 1)

    @orchestrator.send(:persist_worker_exit, "persist-3", status: "failed", error: "timeout")

    ra = Symphony::RunAttempt.where(issue_id: "persist-3").last
    assert_equal "failed", ra.status
    assert_equal "timeout", ra.error
  end

  test "persist_retry and clear_persisted_retry" do
    due = 5.seconds.from_now
    @orchestrator.send(:persist_retry, "persist-4", "TEST-4", attempt: 2, due_at: due, error: "stall")

    entry = Symphony::RetryEntry.find_by(issue_id: "persist-4")
    assert_equal "TEST-4", entry.identifier
    assert_equal 2, entry.attempt
    assert_equal "stall", entry.error

    @orchestrator.send(:clear_persisted_retry, "persist-4")
    assert_nil Symphony::RetryEntry.find_by(issue_id: "persist-4")
  end

  test "persist_codex_totals writes to OrchestratorState" do
    @orchestrator.instance_variable_get(:@codex_totals).merge!(
      input_tokens: 1000, output_tokens: 500, total_tokens: 1500, seconds_running: 42.5
    )

    @orchestrator.send(:persist_codex_totals)

    state = Symphony::OrchestratorState.current
    assert_equal 1000, state.codex_total_input_tokens
    assert_equal 500, state.codex_total_output_tokens
    assert_equal 1500, state.codex_total_tokens
    assert_in_delta 42.5, state.codex_total_seconds_running, 0.01
  end

  test "restore_from_db! restores codex totals and retry entries" do
    # Seed DB state
    Symphony::OrchestratorState.create!(
      codex_total_input_tokens: 2000,
      codex_total_output_tokens: 800,
      codex_total_tokens: 2800,
      codex_total_seconds_running: 100.0
    )

    Symphony::RetryEntry.create!(
      issue_id: "restore-1", identifier: "TEST-R1", attempt: 3,
      due_at: 10.seconds.from_now, error: "network"
    )

    # Create an interrupted run attempt
    Symphony::PersistedIssue.create!(id: "restore-1", identifier: "TEST-R1", state: "In Progress")
    Symphony::RunAttempt.create!(issue_id: "restore-1", attempt: 2, status: "running", started_at: 1.hour.ago)

    @orchestrator.restore_from_db!

    # Codex totals restored
    totals = @orchestrator.instance_variable_get(:@codex_totals)
    assert_equal 2000, totals[:input_tokens]
    assert_equal 800, totals[:output_tokens]
    assert_equal 2800, totals[:total_tokens]
    assert_in_delta 100.0, totals[:seconds_running], 0.01

    # Retry entries restored
    assert_equal 1, @orchestrator.retry_attempts.size
    entry = @orchestrator.retry_attempts["restore-1"]
    assert_equal "TEST-R1", entry[:identifier]
    assert_equal 3, entry[:attempt]
    assert @orchestrator.claimed.include?("restore-1")

    # Running attempts marked interrupted
    ra = Symphony::RunAttempt.find_by(issue_id: "restore-1")
    assert_equal "interrupted", ra.status
    assert_not_nil ra.finished_at
  end

  test "full dispatch-exit-retry cycle persists to DB" do
    issue = Symphony::Issue.new(
      id: "cycle-1", identifier: "CYCLE-1", title: "Cycle test",
      state: "In Progress"
    )
    @tracker.add_issue(issue)

    # Dispatch
    @orchestrator.tick

    assert_equal 1, Symphony::PersistedIssue.count
    assert_equal 1, Symphony::RunAttempt.where(status: "running").count

    # Worker exits abnormally
    @orchestrator.on_worker_exit_abnormal("cycle-1", "CYCLE-1", attempt: 1, error: "process_died")

    ra = Symphony::RunAttempt.where(issue_id: "cycle-1").last
    assert_equal "failed", ra.status

    assert_equal 1, Symphony::RetryEntry.count
    retry_entry = Symphony::RetryEntry.first
    assert_equal "CYCLE-1", retry_entry.identifier

    # Retry fires and dispatches again
    @orchestrator.on_retry_timer("cycle-1")

    assert_equal 0, Symphony::RetryEntry.count
    assert_equal 2, Symphony::RunAttempt.count

    # Normal exit
    @orchestrator.on_worker_exit_normal("cycle-1", "CYCLE-1")

    completed = Symphony::RunAttempt.where(issue_id: "cycle-1", status: "completed")
    assert_equal 1, completed.count
  end

  test "persistence failures do not crash orchestration" do
    issue = Symphony::Issue.new(
      id: "safe-1", identifier: "SAFE-1", title: "Safe test",
      state: "In Progress"
    )
    @tracker.add_issue(issue)

    # Break the DB connection for PersistedIssue to simulate failure
    original_table = Symphony::PersistedIssue.table_name
    Symphony::PersistedIssue.table_name = "nonexistent_table"

    @orchestrator.tick

    # Orchestrator state still works despite DB error
    assert_equal 1, @orchestrator.running.size
  ensure
    Symphony::PersistedIssue.table_name = original_table
  end
end
