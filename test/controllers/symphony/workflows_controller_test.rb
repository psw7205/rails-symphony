require "test_helper"

class Symphony::WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  test "GET /workflows/:id renders workflow runtime snapshot and connection summary" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "workflow-show-1", identifier: "WS-1", title: "Workflow show issue", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick

    get "/workflows/#{workflow.id}"
    assert_response :success
    assert_includes response.body, "Workflow Alpha"
    assert_includes response.body, "memory"
    assert_includes response.body, "codex"
    assert_includes response.body, "WS-1"
  end

  test "GET /workflows/:id renders workflow retry rows" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.send(
      :persist_retry,
      "workflow-retry-1",
      "WR-1",
      attempt: 2,
      due_at: 5.minutes.from_now,
      error: "process_died"
    )
    context.orchestrator.restore_from_db!

    get "/workflows/#{workflow.id}"
    assert_response :success
    assert_includes response.body, "WR-1"
    assert_includes response.body, "process_died"
  end

  test "GET /workflows/:id renders recent run attempts" do
    workflow = build_managed_workflow
    Symphony::PersistedIssue.create!(
      id: "#{workflow.id}:workflow-attempt-1",
      managed_workflow_id: workflow.id,
      source_issue_id: "workflow-attempt-1",
      tracker_kind: "memory",
      identifier: "WA-1",
      title: "Workflow attempt issue",
      state: "In Progress"
    )
    Symphony::RunAttempt.create!(
      issue_id: "#{workflow.id}:workflow-attempt-1",
      managed_workflow_id: workflow.id,
      attempt: 3,
      status: "failed",
      error: "turn_timeout",
      started_at: 10.minutes.ago,
      finished_at: 9.minutes.ago
    )

    get "/workflows/#{workflow.id}"
    assert_response :success
    assert_includes response.body, "Recent attempts"
    assert_includes response.body, "failed"
    assert_includes response.body, "turn_timeout"
  end

  private
    def reset_console_records!
      Symphony::RunAttempt.delete_all
      Symphony::RetryEntry.delete_all
      Symphony::PersistedIssue.delete_all
      Symphony::OrchestratorState.delete_all
      Symphony::ManagedIssue.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end

    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "Workflow Alpha Project", slug: "workflow-alpha-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Workflow Alpha Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Workflow Alpha Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Workflow Alpha",
        slug: "workflow-alpha",
        status: "active",
        prompt_template: "Workflow show prompt",
        runtime_config: { workspace: { root: "workflow-show-workspaces" } }
      )
    end
end
