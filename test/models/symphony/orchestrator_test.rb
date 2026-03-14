require "test_helper"
require "tmpdir"

class Symphony::OrchestratorTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("orch_test")
    @issues = [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "High pri", state: "Todo", priority: 1, created_at: Time.now),
      Symphony::Issue.new(id: "2", identifier: "MT-2", title: "Low pri", state: "Todo", priority: 3, created_at: Time.now),
      Symphony::Issue.new(id: "3", identifier: "MT-3", title: "In progress", state: "In Progress", priority: 2, created_at: Time.now)
    ]
    @tracker = Symphony::Trackers::Memory.new(issues: @issues)
    @workspace = Symphony::Workspace.new(root: @root)
    @dispatched = []

    workflow_file = File.join(@root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nPrompt")
    @store = Symphony::WorkflowStore.new(workflow_file)

    @orchestrator = Symphony::Orchestrator.new(
      tracker: @tracker,
      workspace: @workspace,
      agent: nil,
      workflow_store: @store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue, attempt: attempt } }
    )
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "tick dispatches candidates sorted by priority" do
    @orchestrator.tick
    assert_equal 3, @dispatched.size
    assert_equal %w[MT-1 MT-3 MT-2], @dispatched.map { |d| d[:issue].identifier }
  end

  test "does not dispatch already claimed issues" do
    @orchestrator.tick
    @dispatched.clear
    @orchestrator.tick
    assert_empty @dispatched
  end

  test "respects max_concurrent_agents" do
    workflow_file = File.join(@root, "WORKFLOW2.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\nagent:\n  max_concurrent_agents: 2\n---\nPrompt")
    store = Symphony::WorkflowStore.new(workflow_file)

    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue } }
    )
    orch.tick
    assert_equal 2, @dispatched.size
  end

  test "on_worker_exit_normal schedules continuation retry" do
    @orchestrator.tick
    @orchestrator.on_worker_exit_normal("1", "MT-1")

    assert_equal 2, @orchestrator.running_count
    assert @orchestrator.retry_attempts.key?("1")
    assert_equal 1, @orchestrator.retry_attempts["1"][:attempt]
  end

  test "on_worker_exit_abnormal schedules backoff retry" do
    @orchestrator.tick
    @orchestrator.on_worker_exit_abnormal("1", "MT-1", attempt: 2, error: "crash")

    entry = @orchestrator.retry_attempts["1"]
    assert_equal 2, entry[:attempt]
    assert_equal 20_000, entry[:delay_ms] # 10000 * 2^1
  end

  test "on_retry_timer re-dispatches active issue" do
    @orchestrator.tick
    @orchestrator.on_worker_exit_normal("1", "MT-1")
    @dispatched.clear

    @orchestrator.on_retry_timer("1")
    assert_equal 1, @dispatched.size
    assert_equal "MT-1", @dispatched.first[:issue].identifier
  end

  test "on_retry_timer releases claim when issue not found" do
    @orchestrator.tick
    @orchestrator.on_worker_exit_normal("1", "MT-1")

    # Replace tracker with one that doesn't have issue 1
    empty_tracker = Symphony::Trackers::Memory.new(issues: [])
    @orchestrator.instance_variable_set(:@tracker, empty_tracker)

    @orchestrator.on_retry_timer("1")
    refute @orchestrator.claimed.include?("1")
  end

  test "on_retry_timer requeues when fetch fails" do
    @orchestrator.tick
    @orchestrator.on_worker_exit_normal("1", "MT-1")

    failing_tracker = Object.new
    def failing_tracker.fetch_candidate_issues(active_states:)
      { error: :linear_api_status }
    end

    @orchestrator.instance_variable_set(:@tracker, failing_tracker)
    @orchestrator.on_retry_timer("1")

    assert @orchestrator.retry_attempts.key?("1")
    assert @orchestrator.claimed.include?("1")
  end

  test "blocked todo issues are not dispatched" do
    blocker_issue = Symphony::Issue.new(
      id: "4", identifier: "MT-4", title: "Blocked", state: "Todo", priority: 1,
      blocked_by: [ { "id" => "5", "identifier" => "MT-5", "state" => "In Progress" } ],
      created_at: Time.now
    )
    tracker = Symphony::Trackers::Memory.new(issues: [ blocker_issue ])

    orch = Symphony::Orchestrator.new(
      tracker: tracker, workspace: @workspace, agent: nil,
      workflow_store: @store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue } }
    )
    orch.tick
    assert_empty @dispatched
  end

  test "handle_codex_update updates running entry" do
    @orchestrator.tick
    timestamp = Time.now.utc
    @orchestrator.handle_codex_update("1", { event: :turn_completed, timestamp: timestamp })

    entry = @orchestrator.running["1"]
    assert_equal :turn_completed, entry[:last_codex_event]
    assert_equal timestamp, entry[:last_codex_timestamp]
  end

  # SPEC 17.4.12: Stall detection kills stalled sessions and schedules retry
  test "stall detection removes stalled entry and schedules retry" do
    workflow_file = File.join(@root, "WORKFLOW_STALL.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\ncodex:\n  stall_timeout_ms: 1\n---\nPrompt")
    store = Symphony::WorkflowStore.new(workflow_file)

    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue } }
    )

    orch.tick
    assert_equal 3, orch.running_count

    sleep 0.01 # ensure stall timeout (1ms) is exceeded

    orch.tick # reconciliation detects stall
    assert_equal 0, orch.running_count
    assert orch.retry_attempts.size > 0, "Stalled entries should be scheduled for retry"
  end

  test "slot exhaustion requeues retry with error reason" do
    workflow_file = File.join(@root, "WORKFLOW_SLOT.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\nagent:\n  max_concurrent_agents: 1\n---\nPrompt")
    store = Symphony::WorkflowStore.new(workflow_file)

    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue } }
    )

    orch.tick
    assert_equal 1, orch.running_count

    # Simulate normal exit for a non-running issue and manually inject retry
    orch.instance_variable_get(:@claimed).add("2")
    orch.instance_variable_get(:@retry_attempts)["2"] = {
      identifier: "MT-2", attempt: 1, delay_ms: 1000, due_at: Time.now.utc - 10
    }

    # Retry fires but no slot available (1 running)
    orch.on_retry_timer("2")

    entry = orch.retry_attempts["2"]
    assert entry, "Should be requeued when no slots available"
    assert_equal 2, entry[:attempt]
    assert_includes entry[:error].to_s, "no available orchestrator slots"
  end

  test "dispatch is skipped when workflow reload has active error" do
    @orchestrator.tick
    @dispatched.clear

    @store.instance_variable_set(:@last_error, :workflow_parse_error)
    @orchestrator.tick

    assert_empty @dispatched
  end

  # SPEC 17.4.3: Todo issue with terminal blockers IS eligible
  test "todo issue with terminal blockers is dispatched" do
    issue = Symphony::Issue.new(
      id: "6", identifier: "MT-6", title: "Unblocked todo", state: "Todo", priority: 1,
      blocked_by: [ { "id" => "7", "identifier" => "MT-7", "state" => "Done" } ],
      created_at: Time.now
    )
    tracker = Symphony::Trackers::Memory.new(issues: [ issue ])

    orch = Symphony::Orchestrator.new(
      tracker: tracker, workspace: @workspace, agent: nil,
      workflow_store: @store,
      on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue } }
    )
    orch.tick
    assert_equal 1, @dispatched.size
    assert_equal "MT-6", @dispatched.first[:issue].identifier
  end
end
