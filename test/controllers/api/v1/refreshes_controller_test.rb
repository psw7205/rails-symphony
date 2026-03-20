require "test_helper"
require "tmpdir"

class Api::V1::RefreshesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Symphony::WorkflowRuntimeManager.clear!
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
    Symphony::WorkflowRuntimeManager.clear!
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

  test "POST /api/v1/workflows/:workflow_id/refresh triggers the workflow refresh" do
    workflow = build_managed_workflow

    post "/api/v1/workflows/#{workflow.id}/refresh"
    assert_response 202

    body = JSON.parse(response.body)
    assert body["queued"]
    assert_includes body["operations"], "poll"
    assert_includes body["operations"], "reconcile"
  end

  private
    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "API Refresh Project", slug: "api-refresh-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "API Refresh Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "API Refresh Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "API Refresh Workflow",
        slug: "api-refresh-workflow",
        status: "active",
        prompt_template: "Refresh prompt",
        runtime_config: { workspace: { root: "api-refresh-workspaces" } }
      )
    end
end
