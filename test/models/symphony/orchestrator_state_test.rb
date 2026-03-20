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
