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

  test "GET /projects/new renders the project form" do
    get "/projects/new"
    assert_response :success
    assert_includes response.body, "New project"
  end

  test "POST /projects creates a managed project" do
    post "/projects", params: {
      managed_project: {
        name: "Created Project",
        slug: "created-project",
        status: "active",
        description: "Created from controller test"
      }
    }

    assert_redirected_to "/projects/#{Symphony::ManagedProject.last.id}"
    assert_equal "Created Project", Symphony::ManagedProject.last.name
  end

  test "POST /projects renders validation errors" do
    post "/projects", params: {
      managed_project: {
        name: "",
        slug: "",
        status: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Name can&#39;t be blank"
  end

  test "GET /projects/:id/edit renders the project form" do
    project = Symphony::ManagedProject.create!(name: "Editable Project", slug: "editable-project", status: "active")

    get "/projects/#{project.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit project"
    assert_includes response.body, "Editable Project"
  end

  test "PATCH /projects/:id updates a managed project" do
    project = Symphony::ManagedProject.create!(name: "Editable Project", slug: "editable-project", status: "active")

    patch "/projects/#{project.id}", params: {
      managed_project: {
        name: "Updated Project",
        slug: "updated-project",
        status: "inactive",
        description: "Updated from controller test"
      }
    }

    assert_redirected_to "/projects/#{project.id}"
    assert_equal "Updated Project", project.reload.name
    assert_equal "inactive", project.status
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
