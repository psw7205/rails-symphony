require "test_helper"

class Symphony::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
  end

  teardown do
    reset_console_records!
  end

  test "GET /projects renders managed projects" do
    Symphony::ManagedProject.create!(name: "Project Alpha", slug: "project-alpha", status: "active")
    Symphony::ManagedProject.create!(name: "Project Beta", slug: "project-beta", status: "inactive")

    get "/projects"
    assert_response :success
    assert_includes response.body, "Project Alpha"
    assert_includes response.body, "Project Beta"
  end

  test "GET /projects/:id renders project workflows and health" do
    project = Symphony::ManagedProject.create!(name: "Project Alpha", slug: "project-alpha", status: "active")
    tracker_connection = Symphony::TrackerConnection.create!(
      name: "Project Alpha Memory",
      kind: "memory",
      status: "active",
      config: {}
    )
    agent_connection = Symphony::AgentConnection.create!(
      name: "Project Alpha Codex",
      kind: "codex",
      status: "active",
      config: { codex: { command: "bin/codex app-server" } }
    )
    workflow = Symphony::ManagedWorkflow.create!(
      managed_project: project,
      tracker_connection: tracker_connection,
      agent_connection: agent_connection,
      name: "Alpha Workflow",
      slug: "alpha-workflow",
      status: "active",
      prompt_template: "Project show prompt",
      runtime_config: { workspace: { root: "project-show-workspaces" } }
    )

    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "project-show-1", identifier: "PS-1", title: "Project show issue", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick

    get "/projects/#{project.id}"
    assert_response :success
    assert_includes response.body, "Project Alpha"
    assert_includes response.body, "Alpha Workflow"
    assert_includes response.body, "memory"
    assert_match(/<td>1<\/td>/, response.body)
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
end
