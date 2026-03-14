require "test_helper"
require "tmpdir"

class Symphony::OrchestratorSnapshotTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("snap_test")
    workflow_file = File.join(@root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nPrompt")
    @store = Symphony::WorkflowStore.new(workflow_file)

    @tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "T1", state: "In Progress", priority: 1, created_at: Time.now),
      Symphony::Issue.new(id: "2", identifier: "MT-2", title: "T2", state: "Todo", priority: 2, created_at: Time.now)
    ])
    @workspace = Symphony::Workspace.new(root: File.join(@root, "ws"))
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "snapshot returns running and retry entries" do
    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: @store,
      on_dispatch: ->(_i, _a) {}
    )

    orch.tick
    snap = orch.snapshot

    assert_equal 2, snap[:counts][:running]
    assert_equal 0, snap[:counts][:retrying]
    assert snap[:generated_at].present?
    assert_equal 2, snap[:running].size
    assert_equal "MT-1", snap[:running].first[:issue_identifier]

    # Worker exits → retry entry appears
    orch.on_worker_exit_abnormal("1", "MT-1", attempt: 1, error: "crash")

    snap = orch.snapshot
    assert_equal 1, snap[:counts][:running]
    assert_equal 1, snap[:counts][:retrying]
    assert_equal "MT-1", snap[:retrying].first[:issue_identifier]
    assert_equal "crash", snap[:retrying].first[:error]
  end

  test "snapshot accumulates codex runtime on worker exit" do
    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: @store,
      on_dispatch: ->(_i, _a) {}
    )
    orch.tick
    sleep 0.05 # accumulate some runtime

    orch.on_worker_exit_normal("1", "MT-1")
    snap = orch.snapshot

    assert snap[:codex_totals][:seconds_running] > 0
  end

  test "snapshot tracks token usage from codex updates" do
    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: @store,
      on_dispatch: ->(_i, _a) {}
    )
    orch.tick

    orch.handle_codex_update("1", {
      event: :turn_completed,
      usage: { input_tokens: 100, output_tokens: 50, total_tokens: 150 }
    })

    snap = orch.snapshot
    assert_equal 100, snap[:codex_totals][:input_tokens]
    assert_equal 50, snap[:codex_totals][:output_tokens]
    assert_equal 150, snap[:codex_totals][:total_tokens]
  end

  test "request_refresh triggers tick and returns payload" do
    orch = Symphony::Orchestrator.new(
      tracker: @tracker, workspace: @workspace, agent: nil,
      workflow_store: @store,
      on_dispatch: ->(_i, _a) {}
    )

    result = orch.request_refresh
    assert result[:queued]
    assert_includes result[:operations], "poll"
    assert result[:requested_at].present?
  end
end
