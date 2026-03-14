require "test_helper"
require "tmpdir"

class Api::V1::StatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @root = Dir.mktmpdir("api_test")
    workflow_file = File.join(@root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nPrompt")

    store = Symphony::WorkflowStore.new(workflow_file)
    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Test", state: "In Progress", priority: 1, created_at: Time.now)
    ])
    workspace = Symphony::Workspace.new(root: File.join(@root, "ws"))

    Symphony.orchestrator = Symphony::Orchestrator.new(
      tracker: tracker, workspace: workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(_issue, _attempt) {}
    )
    Symphony.workspace = workspace
    Symphony.orchestrator.tick
  end

  teardown do
    Symphony.orchestrator = nil
    Symphony.workspace = nil
    FileUtils.rm_rf(@root)
  end

  test "GET /api/v1/state returns snapshot" do
    get api_v1_state_path
    assert_response :success

    body = JSON.parse(response.body)
    assert body.key?("generated_at")
    assert_equal 1, body["counts"]["running"]
    assert_equal 0, body["counts"]["retrying"]
    assert body.key?("codex_totals")
    assert body.key?("running")
  end

  test "GET /api/v1/state returns 503 when orchestrator nil" do
    Symphony.orchestrator = nil
    get api_v1_state_path
    assert_response 503

    body = JSON.parse(response.body)
    assert_equal "orchestrator_unavailable", body["error"]["code"]
  end
end
