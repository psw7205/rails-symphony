require "test_helper"

class Symphony::WorkflowOperationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    reset_console_records!
  end

  teardown do
    clear_enqueued_jobs
    reset_console_records!
  end

  test "POST /workflows/:workflow_id/pause marks the workflow inactive" do
    workflow = build_workflow(status: "active", slug: "operations-pause", name: "Operations Pause")

    post "/workflows/#{workflow.id}/pause"

    assert_redirected_to "/workflows/#{workflow.id}"
    assert_equal "inactive", workflow.reload.status
  end

  test "POST /workflows/:workflow_id/resume marks the workflow active and enqueues a refresh" do
    workflow = build_workflow(status: "inactive", slug: "operations-resume", name: "Operations Resume")

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      post "/workflows/#{workflow.id}/resume"
    end

    assert_redirected_to "/workflows/#{workflow.id}"
    trigger_event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal "active", workflow.reload.status
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "manual_refresh", trigger_event.source
  end

  test "POST /workflows/:workflow_id/refresh_now enqueues a manual refresh only for active workflows" do
    workflow = build_workflow(status: "active", slug: "operations-refresh", name: "Operations Refresh")

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      post "/workflows/#{workflow.id}/refresh_now"
    end

    assert_redirected_to "/workflows/#{workflow.id}"
    trigger_event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "manual_refresh", trigger_event.source
  end

  test "POST workflow operations reject invalid transitions" do
    active_workflow = build_workflow(status: "active", slug: "operations-active", name: "Operations Active")
    inactive_workflow = build_workflow(status: "inactive", slug: "operations-inactive", name: "Operations Inactive")

    assert_no_difference("Symphony::WorkflowTriggerEvent.count") do
      post "/workflows/#{active_workflow.id}/resume"
      post "/workflows/#{inactive_workflow.id}/pause"
      post "/workflows/#{inactive_workflow.id}/refresh_now"
    end

    assert_redirected_to "/workflows/#{inactive_workflow.id}"
    assert_equal "active", active_workflow.reload.status
    assert_equal "inactive", inactive_workflow.reload.status
    assert_equal 0, enqueued_jobs.size
  end

  private
    def reset_console_records!
      Symphony::OrchestratorState.delete_all
      Symphony::WorkflowTriggerEvent.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end

    def build_workflow(status:, slug:, name:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "#{name} Tracker", kind: "memory", status: "active", config: {})
      agent_connection = Symphony::AgentConnection.create!(name: "#{name} Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: status,
        prompt_template: "Operations prompt",
        runtime_config: { workspace: { root: "operations-workspaces" } }
      )
    end
end
