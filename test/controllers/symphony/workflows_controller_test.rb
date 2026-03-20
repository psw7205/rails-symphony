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

  test "GET /workflows/new renders the workflow form" do
    project = Symphony::ManagedProject.create!(name: "Workflow Form Project", slug: "workflow-form-project", status: "active")
    tracker_connection = Symphony::TrackerConnection.create!(name: "Workflow Form Tracker", kind: "memory", status: "active", config: {})
    agent_connection = Symphony::AgentConnection.create!(name: "Workflow Form Agent", kind: "codex", status: "active", config: {})

    get "/workflows/new"
    assert_response :success
    assert_includes response.body, "New workflow"
    assert_includes response.body, project.name
    assert_includes response.body, tracker_connection.name
    assert_includes response.body, agent_connection.name
  end

  test "POST /workflows creates a managed workflow" do
    project = Symphony::ManagedProject.create!(name: "Workflow Create Project", slug: "workflow-create-project", status: "active")
    tracker_connection = Symphony::TrackerConnection.create!(name: "Workflow Create Tracker", kind: "memory", status: "active", config: {})
    agent_connection = Symphony::AgentConnection.create!(name: "Workflow Create Agent", kind: "codex", status: "active", config: {})

    post "/workflows", params: {
      managed_workflow: {
        managed_project_id: project.id,
        tracker_connection_id: tracker_connection.id,
        agent_connection_id: agent_connection.id,
        name: "Created Workflow",
        slug: "created-workflow",
        status: "active",
        prompt_template: "Created workflow prompt",
        runtime_config_json: "{\"workspace\":{\"root\":\"created-workflow-workspaces\"}}"
      }
    }

    workflow = Symphony::ManagedWorkflow.order(:id).last
    assert_redirected_to "/workflows/#{workflow.id}"
    assert_equal "Created Workflow", workflow.name
    assert_equal "created-workflow-workspaces", workflow.runtime_config["workspace"]["root"]
  end

  test "POST /workflows renders validation errors" do
    post "/workflows", params: {
      managed_workflow: {
        managed_project_id: "",
        tracker_connection_id: "",
        agent_connection_id: "",
        name: "",
        slug: "",
        status: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Name can&#39;t be blank"
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

  test "GET /workflows/:id renders token and runtime totals" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.instance_variable_get(:@codex_totals).merge!(
      input_tokens: 120,
      output_tokens: 30,
      total_tokens: 150,
      seconds_running: 180.0
    )

    get "/workflows/#{workflow.id}"
    assert_response :success
    assert_includes response.body, "Total tokens"
    assert_includes response.body, "150"
    assert_includes response.body, "3m 0s"
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
