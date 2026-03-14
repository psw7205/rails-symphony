require "test_helper"
require "tmpdir"

class Api::V1::IssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @root = Dir.mktmpdir("api_issue_test")
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
      on_dispatch: ->(_issue, _attempt) { }
    )
    Symphony.workspace = workspace
    Symphony.orchestrator.tick
  end

  teardown do
    Symphony.orchestrator = nil
    Symphony.workspace = nil
    FileUtils.rm_rf(@root)
  end

  test "GET /api/v1/:identifier returns issue details" do
    get api_v1_issue_path("MT-1")
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "MT-1", body["issue_identifier"]
    assert_equal "running", body["status"]
    assert body["running"].present?
  end

  test "GET /api/v1/:identifier returns 404 for unknown issue" do
    get api_v1_issue_path("UNKNOWN-99")
    assert_response 404

    body = JSON.parse(response.body)
    assert_equal "issue_not_found", body["error"]["code"]
  end
end
