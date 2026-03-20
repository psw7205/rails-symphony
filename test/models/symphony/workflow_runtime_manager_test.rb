require "test_helper"

class Symphony::WorkflowRuntimeManagerTest < ActiveSupport::TestCase
  test "fetch caches runtime contexts by workflow id" do
    workflow = build_managed_workflow

    first_context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    second_context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)

    assert_equal workflow.id, first_context.managed_workflow.id
    assert_same first_context, second_context
  end

  private
    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "Runtime Manager Project", slug: "runtime-manager-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Runtime Manager Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Runtime Manager Codex",
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
        name: "Runtime Manager Workflow",
        slug: "runtime-manager-workflow",
        status: "active",
        prompt_template: "Prompt from runtime manager",
        runtime_config: {
          workspace: { root: "runtime-manager-workspaces" }
        }
      )
    end
end
