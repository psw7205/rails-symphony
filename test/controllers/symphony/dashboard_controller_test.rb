require "test_helper"

class Symphony::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "GET / renders dashboard without orchestrator" do
    Symphony.orchestrator = nil
    get root_path
    assert_response :success
    assert_includes response.body, "Operations Dashboard"
    assert_includes response.body, "No active sessions"
  end

  test "GET / renders managed workflow rows" do
    build_managed_workflow(slug: "dashboard-workflow-one", name: "Dashboard Workflow One")
    build_managed_workflow(slug: "dashboard-workflow-two", name: "Dashboard Workflow Two")

    get root_path
    assert_response :success
    assert_includes response.body, "Dashboard Workflow One"
    assert_includes response.body, "Dashboard Workflow Two"
  end

  private
    def build_managed_workflow(slug:, name:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "#{name} Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "#{name} Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: "active",
        prompt_template: "Dashboard prompt",
        runtime_config: { workspace: { root: "dashboard-workspaces" } }
      )
    end
end
