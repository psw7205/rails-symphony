require "test_helper"

class Symphony::WorkflowTriggerSchedulerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  teardown do
    clear_enqueued_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  test "enqueue records an enqueued trigger event and workflow poll job" do
    workflow = build_managed_workflow(
      slug: "scheduler-manual-workflow",
      name: "Scheduler Manual Workflow"
    )

    result = nil
    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      result = Symphony::WorkflowTriggerScheduler.enqueue(
        workflow_id: workflow.id,
        source: "manual_refresh"
      )
    end

    event = Symphony::WorkflowTriggerEvent.order(:id).last
    job = enqueued_jobs.last
    assert_equal true, result[:queued]
    assert_equal false, result[:coalesced]
    assert_equal "manual_refresh", result[:source]
    assert_equal event.id, result[:trigger_event_id]
    assert_equal "enqueued", event.status
    assert_equal "manual_refresh", event.source
    assert_equal "not_applicable", event.signature_state
    assert_equal workflow.id, job[:args].first["workflow_id"]
    assert_equal event.id, job[:args].first["trigger_event_id"]
  end

  test "enqueue coalesces overlapping non-webhook requests while a trigger is still open" do
    workflow = build_managed_workflow(
      slug: "scheduler-coalesce-workflow",
      name: "Scheduler Coalesce Workflow"
    )
    Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "manual_refresh",
      status: "running",
      signature_state: "not_applicable",
      requested_at: 1.minute.ago,
      started_at: 30.seconds.ago
    )

    result = Symphony::WorkflowTriggerScheduler.enqueue(
      workflow_id: workflow.id,
      source: "manual_refresh"
    )

    ignored_event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal false, result[:queued]
    assert_equal true, result[:coalesced]
    assert_equal "ignored_duplicate", ignored_event.status
    assert_equal 0, enqueued_jobs.size
  end

  test "enqueue records ignored duplicate webhook deliveries without enqueueing another job" do
    workflow = build_managed_workflow(
      slug: "scheduler-webhook-workflow",
      name: "Scheduler Webhook Workflow"
    )
    Symphony::WorkflowTriggerScheduler.enqueue(
      workflow_id: workflow.id,
      source: "webhook_github",
      provider: "github",
      delivery_id: "delivery-123",
      signature_state: "verified"
    )
    clear_enqueued_jobs

    result = Symphony::WorkflowTriggerScheduler.enqueue(
      workflow_id: workflow.id,
      source: "webhook_github",
      provider: "github",
      delivery_id: "delivery-123",
      signature_state: "verified"
    )

    ignored_event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal false, result[:queued]
    assert_equal true, result[:coalesced]
    assert_equal "ignored_duplicate", ignored_event.status
    assert_equal "delivery-123", ignored_event.delivery_id
    assert_equal 0, enqueued_jobs.size
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

    def build_managed_workflow(slug:, name:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "#{name} Tracker", kind: "memory", status: "active", config: {})
      agent_connection = Symphony::AgentConnection.create!(name: "#{name} Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: "active",
        prompt_template: "Scheduler prompt",
        runtime_config: { workspace: { root: "scheduler-workspaces" } }
      )
    end
end
