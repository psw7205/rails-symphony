require "test_helper"

class Symphony::WorkflowRuntimeFactoryTest < ActiveSupport::TestCase
  test "build creates a runtime context for a managed workflow" do
    workflow = build_managed_workflow

    context = Symphony::WorkflowRuntimeFactory.build(workflow.id)

    assert_equal workflow.id, context.managed_workflow.id
    assert_instance_of Symphony::Trackers::Memory, context.tracker
    assert_instance_of Symphony::Workspace, context.workspace
    assert_instance_of Symphony::Agents::Codex, context.agent
    assert_instance_of Symphony::ManagedWorkflowStore, context.workflow_store
    assert_instance_of Symphony::Orchestrator, context.orchestrator
    assert_equal workflow.id, context.orchestrator.managed_workflow_id
    assert_equal 0, context.orchestrator.snapshot[:counts][:running]
  end

  private
    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "Runtime Factory Project", slug: "runtime-factory-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Runtime Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Runtime Codex",
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
        name: "Runtime Factory Workflow",
        slug: "runtime-factory-workflow",
        status: "active",
        prompt_template: "Prompt from runtime factory",
        runtime_config: {
          workspace: { root: "runtime-factory-workspaces" }
        }
      )
    end
end
