require "test_helper"

class Symphony::OrchestratorStateTest < ActiveSupport::TestCase
  test "belongs to managed workflow" do
    association = Symphony::OrchestratorState.reflect_on_association(:managed_workflow)

    assert_not_nil association
    assert_equal :belongs_to, association.macro
  end

  test "for_workflow! reuses the same row for the same workflow" do
    workflow, = build_managed_workflows

    first_state = Symphony::OrchestratorState.for_workflow!(workflow.id)
    second_state = Symphony::OrchestratorState.for_workflow!(workflow.id)

    assert_equal first_state.id, second_state.id
    assert_equal workflow.id, first_state.managed_workflow_id
  end

  test "for_workflow! creates separate rows for different workflows" do
    first_workflow, second_workflow = build_managed_workflows

    first_state = Symphony::OrchestratorState.for_workflow!(first_workflow.id)
    second_state = Symphony::OrchestratorState.for_workflow!(second_workflow.id)

    assert_not_equal first_state.id, second_state.id
    assert_equal first_workflow.id, first_state.managed_workflow_id
    assert_equal second_workflow.id, second_state.managed_workflow_id
  end

  test "current uses a nil-scoped legacy singleton row even when managed workflow states exist" do
    workflow, = build_managed_workflows
    Symphony::OrchestratorState.for_workflow!(workflow.id)

    state = Symphony::OrchestratorState.current

    assert_nil state.managed_workflow_id
  end

  test "disallows duplicate summary rows for the same managed workflow" do
    workflow, = build_managed_workflows
    Symphony::OrchestratorState.for_workflow!(workflow.id)

    duplicate_state = Symphony::OrchestratorState.new(managed_workflow: workflow)

    assert_not duplicate_state.valid?
    assert_includes duplicate_state.errors[:managed_workflow_id], "has already been taken"
  end

  test "belongs to last workflow trigger event" do
    association = Symphony::OrchestratorState.reflect_on_association(:last_workflow_trigger_event)

    assert_not_nil association
    assert_equal :belongs_to, association.macro
  end

  test "persists trigger and tick health summary fields" do
    workflow, = build_managed_workflows
    trigger_event = Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "manual_refresh",
      status: "succeeded",
      signature_state: "not_applicable",
      requested_at: 2.minutes.ago,
      started_at: 90.seconds.ago,
      finished_at: 1.minute.ago
    )

    state = Symphony::OrchestratorState.for_workflow!(workflow.id)
    state.update!(
      last_trigger_source: "manual_refresh",
      last_triggered_at: Time.current,
      last_tick_started_at: 90.seconds.ago,
      last_tick_finished_at: 1.minute.ago,
      last_tick_status: "succeeded",
      last_tick_error: "none",
      last_workflow_trigger_event: trigger_event
    )

    state.reload
    assert_equal "manual_refresh", state.last_trigger_source
    assert_equal "succeeded", state.last_tick_status
    assert_equal "none", state.last_tick_error
    assert_equal trigger_event.id, state.last_workflow_trigger_event_id
  end

  private
    def build_managed_workflows
      project = Symphony::ManagedProject.create!(name: "State Project", slug: "state-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "Linear State", kind: "linear", status: "active")
      agent_connection = Symphony::AgentConnection.create!(name: "Codex State", kind: "codex", status: "active")

      [
        Symphony::ManagedWorkflow.create!(
          managed_project: project,
          tracker_connection: tracker_connection,
          agent_connection: agent_connection,
          name: "State One",
          slug: "state-one",
          status: "active"
        ),
        Symphony::ManagedWorkflow.create!(
          managed_project: project,
          tracker_connection: tracker_connection,
          agent_connection: agent_connection,
          name: "State Two",
          slug: "state-two",
          status: "active"
        )
      ]
    end
end
