require "test_helper"

class Symphony::WorkflowScopedRuntimeIntegrationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  test "managed workflow poll dispatches work, persists attempts, and renders on the dashboard" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(
        id: "integration-workflow-1",
        identifier: "INT-1",
        title: "Integration workflow issue",
        state: "In Progress",
        priority: 1,
        created_at: Time.current
      )
    )

    assert_enqueued_with(
      job: Symphony::AgentWorkerJob,
      args: [ {
        issue_id: "integration-workflow-1",
        issue_identifier: "INT-1",
        issue_title: "Integration workflow issue",
        issue_state: "In Progress",
        attempt: nil,
        managed_workflow_id: workflow.id
      } ]
    ) do
      Symphony::WorkflowPollJob.perform_now(workflow_id: workflow.id)
    end

    persisted_issue = Symphony::PersistedIssue.find("#{workflow.id}:integration-workflow-1")
    run_attempt = Symphony::RunAttempt.order(:id).last

    assert_equal workflow.id, persisted_issue.managed_workflow_id
    assert_equal "integration-workflow-1", persisted_issue.source_issue_id
    assert_equal "running", run_attempt.status
    assert_equal workflow.id, run_attempt.managed_workflow_id

    context.orchestrator.on_worker_exit_abnormal(
      "integration-workflow-1",
      "INT-1",
      attempt: 1,
      error: "process_died"
    )

    run_attempt.reload
    assert_equal "failed", run_attempt.status
    assert_equal "process_died", run_attempt.error

    get root_path

    assert_response :success
    assert_includes response.body, workflow.name
    assert_includes response.body, "INT-1"
    assert_includes response.body, "process_died"
  end

  private
    def reset_console_records!
      Symphony::RunAttempt.delete_all
      Symphony::RetryEntry.delete_all
      Symphony::PersistedIssue.delete_all
      Symphony::OrchestratorState.delete_all
      Symphony::WorkflowTriggerEvent.delete_all
      Symphony::ManagedIssue.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end

    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "Integration Project", slug: "integration-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Integration Memory Tracker",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Integration Codex Agent",
        kind: "codex",
        status: "active",
        config: {
          codex: { command: "bin/codex app-server" }
        }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Integration Workflow",
        slug: "integration-workflow",
        status: "active",
        prompt_template: "Integration prompt",
        runtime_config: {
          workspace: { root: "integration-workspaces" }
        }
      )
    end
end
