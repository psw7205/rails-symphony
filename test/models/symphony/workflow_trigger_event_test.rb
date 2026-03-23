require "test_helper"

class Symphony::WorkflowTriggerEventTest < ActiveSupport::TestCase
  test "requires a managed workflow and valid status" do
    event = Symphony::WorkflowTriggerEvent.new(
      source: "poll",
      status: "unknown",
      requested_at: Time.current
    )

    assert_not event.valid?
    assert_includes event.errors[:managed_workflow], "must exist"
    assert_includes event.errors[:status], "is not included in the list"
  end

  test "belongs to managed workflow" do
    workflow = build_managed_workflow(
      slug: "trigger-ledger-workflow",
      name: "Trigger Ledger Workflow"
    )
    event = Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "manual_refresh",
      status: "accepted",
      signature_state: "not_applicable",
      requested_at: Time.current
    )

    assert_equal workflow.id, event.managed_workflow_id
  end

  test "duplicate_delivery? matches prior provider delivery for the same workflow" do
    workflow = build_managed_workflow(
      slug: "trigger-duplicate-workflow",
      name: "Trigger Duplicate Workflow"
    )
    other_workflow = build_managed_workflow(
      slug: "trigger-duplicate-other-workflow",
      name: "Trigger Duplicate Other Workflow"
    )
    Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "webhook_github",
      provider: "github",
      delivery_id: "delivery-123",
      status: "accepted",
      signature_state: "verified",
      requested_at: Time.current
    )

    assert Symphony::WorkflowTriggerEvent.duplicate_delivery?(
      managed_workflow_id: workflow.id,
      provider: "github",
      delivery_id: "delivery-123"
    )
    assert_not Symphony::WorkflowTriggerEvent.duplicate_delivery?(
      managed_workflow_id: other_workflow.id,
      provider: "github",
      delivery_id: "delivery-123"
    )
  end

  test "recent scopes expose accepted and failed trigger rows" do
    workflow = build_managed_workflow(
      slug: "trigger-scope-workflow",
      name: "Trigger Scope Workflow"
    )

    accepted = Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "poll",
      status: "succeeded",
      signature_state: "not_applicable",
      requested_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    failed = Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "webhook_github",
      provider: "github",
      delivery_id: "delivery-failed",
      status: "failed",
      signature_state: "verified",
      requested_at: Time.current,
      error: "tick_failed"
    )

    assert_includes Symphony::WorkflowTriggerEvent.recent_accepted, accepted
    assert_includes Symphony::WorkflowTriggerEvent.recent_failures, failed
    assert_includes Symphony::WorkflowTriggerEvent.unresolved_failures, failed
  end

  private
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
        status: "active"
      )
    end
end
