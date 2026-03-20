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
    assert_includes response.body, "Projects"
    assert_includes response.body, "Active workflows"
    assert_includes response.body, "Dashboard Workflow One"
    assert_includes response.body, "Dashboard Workflow Two"
  end

  test "GET / renders running metric from managed workflow totals" do
    workflow = build_managed_workflow(slug: "dashboard-running-workflow", name: "Dashboard Running Workflow")
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "dashboard-running-1", identifier: "DR-1", title: "Dashboard running", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick

    get root_path
    assert_response :success
    assert_match(/<p class="metric-label">Running<\/p>\s*<p class="metric-value numeric">1<\/p>/, response.body)
  end

  test "GET / renders managed running sessions" do
    workflow = build_managed_workflow(slug: "dashboard-running-session-workflow", name: "Dashboard Running Session Workflow")
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "dashboard-running-session-1", identifier: "DRS-1", title: "Dashboard running session", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick

    get root_path
    assert_response :success
    assert_includes response.body, "DRS-1"
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
