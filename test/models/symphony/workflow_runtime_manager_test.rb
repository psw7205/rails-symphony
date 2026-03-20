require "test_helper"

class Symphony::WorkflowRuntimeManagerTest < ActiveSupport::TestCase
  test "fetch caches runtime contexts by workflow id" do
    workflow = build_managed_workflow

    first_context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    second_context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)

    assert_equal workflow.id, first_context.managed_workflow.id
    assert_same first_context, second_context
  end

  test "refresh rebuilds the cached runtime context" do
    workflow = build_managed_workflow

    original_context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    workflow.update!(
      prompt_template: "Updated runtime manager prompt",
      runtime_config: { workspace: { root: "updated-runtime-manager-workspaces" } }
    )

    refreshed_context = Symphony::WorkflowRuntimeManager.refresh(workflow.id)

    refute_same original_context, refreshed_context
    assert_equal "Updated runtime manager prompt", refreshed_context.workflow_store.prompt_template
    assert_equal "updated-runtime-manager-workspaces", refreshed_context.workflow_store.service_config.workspace_root
  end

  test "snapshot returns the workflow specific orchestrator snapshot" do
    workflow = build_managed_workflow

    snapshot = Symphony::WorkflowRuntimeManager.snapshot(workflow.id)

    assert_equal 0, snapshot[:counts][:running]
    assert_equal 0, snapshot[:counts][:retrying]
    assert_equal [], snapshot[:running]
    assert_equal [], snapshot[:retrying]
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
