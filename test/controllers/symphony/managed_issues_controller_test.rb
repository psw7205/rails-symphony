require "test_helper"

class Symphony::ManagedIssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
  end

  teardown do
    reset_console_records!
  end

  test "GET /workflows/:workflow_id/issues renders managed issues for database workflows" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-workflow", name: "Managed Issues Workflow")
    Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-1",
      title: "Managed issue one",
      state: "Todo"
    )

    get "/workflows/#{workflow.id}/issues"
    assert_response :success
    assert_includes response.body, "MI-1"
    assert_includes response.body, "Managed issue one"
  end

  test "GET /workflows/:workflow_id/issues returns 404 for non-database workflows" do
    workflow = build_managed_workflow(tracker_kind: "memory", slug: "non-database-workflow", name: "Non Database Workflow")

    get "/workflows/#{workflow.id}/issues"
    assert_response :not_found
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

    def build_managed_workflow(tracker_kind:, slug:, name:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "#{name} Tracker", kind: tracker_kind, status: "active", config: {})
      agent_connection = Symphony::AgentConnection.create!(name: "#{name} Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: "active"
      )
    end
end
