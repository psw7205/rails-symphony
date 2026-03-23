require "test_helper"
require "tmpdir"

class Api::V1::RefreshesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
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
    clear_enqueued_jobs
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

  test "POST /api/v1/workflows/:workflow_id/refresh enqueues an async workflow refresh" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.define_singleton_method(:tick) do
      raise "workflow refresh should not tick in the request thread"
    end

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      post "/api/v1/workflows/#{workflow.id}/refresh"
    end
    assert_response 202

    body = JSON.parse(response.body)
    job = enqueued_jobs.last
    assert body["queued"]
    assert_equal "manual_refresh", body["source"]
    assert body["trigger_event_id"].present?
    trigger_event = Symphony::WorkflowTriggerEvent.find(body["trigger_event_id"])
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "manual_refresh", trigger_event.source
    assert_equal "enqueued", trigger_event.status
    assert_equal workflow.id, job[:args].first["workflow_id"]
    assert_equal trigger_event.id, job[:args].first["trigger_event_id"]
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
