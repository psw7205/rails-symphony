require "test_helper"
require "tmpdir"

class Api::V1::RefreshesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @root = Dir.mktmpdir("api_refresh_test")
    workflow_file = File.join(@root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nPrompt")

    store = Symphony::WorkflowStore.new(workflow_file)
    tracker = Symphony::Trackers::Memory.new(issues: [])
    workspace = Symphony::Workspace.new(root: File.join(@root, "ws"))

    Symphony.orchestrator = Symphony::Orchestrator.new(
      tracker: tracker, workspace: workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(_issue, _attempt) { }
    )
  end

  teardown do
    Symphony.orchestrator = nil
    FileUtils.rm_rf(@root)
  end

  test "POST /api/v1/refresh triggers poll and returns 202" do
    post api_v1_refresh_path
    assert_response 202

    body = JSON.parse(response.body)
    assert body["queued"]
    assert_includes body["operations"], "poll"
    assert_includes body["operations"], "reconcile"
  end

  test "POST /api/v1/refresh returns 503 when orchestrator nil" do
    Symphony.orchestrator = nil
    post api_v1_refresh_path
    assert_response 503
  end
end
