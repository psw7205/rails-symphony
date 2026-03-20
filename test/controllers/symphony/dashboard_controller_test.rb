require "test_helper"

class Symphony::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  test "GET / renders dashboard without orchestrator" do
    Symphony.orchestrator = nil
    get root_path
    assert_response :success
    assert_includes response.body, "Operations Dashboard"
    assert_includes response.body, "No active workflows."
    refute_includes response.body, "No active sessions."
  end

  test "GET / renders managed workflow rows" do
    build_managed_workflow(slug: "dashboard-workflow-one", name: "Dashboard Workflow One")
    build_managed_workflow(slug: "dashboard-workflow-two", name: "Dashboard Workflow Two")

    get root_path
    assert_response :success
    assert_includes response.body, "Projects"
    assert_includes response.body, "Active workflows"
    assert_includes response.body, "Tracker"
    assert_includes response.body, "memory"
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
    assert_includes response.body, "/api/v1/workflows/#{workflow.id}/issues/DRS-1"
  end

  test "GET / renders token and runtime metrics from managed workflow totals" do
    workflow = build_managed_workflow(slug: "dashboard-totals-workflow", name: "Dashboard Totals Workflow")
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.instance_variable_get(:@codex_totals).merge!(
      input_tokens: 120,
      output_tokens: 30,
      total_tokens: 150,
      seconds_running: 180.0
    )

    get root_path
    assert_response :success
    assert_match(/<p class="metric-label">Total tokens<\/p>\s*<p class="metric-value numeric">150<\/p>/, response.body)
    assert_match(/<p class="metric-label">Runtime<\/p>\s*<p class="metric-value numeric">3m 0s<\/p>/, response.body)
  end

  test "GET / renders rate limits from managed workflow snapshots" do
    workflow = build_managed_workflow(slug: "dashboard-rate-limit-workflow", name: "Dashboard Rate Limit Workflow")
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.instance_variable_set(
      :@codex_rate_limits,
      { "remaining" => 7, "reset_at" => "2026-03-20T12:00:00Z" }
    )

    get root_path
    assert_response :success
    assert_includes response.body, "dashboard-rate-limit-workflow"
    assert_includes response.body, "remaining"
    assert_includes response.body, "7"
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
