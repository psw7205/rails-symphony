require "test_helper"

class Symphony::ManagedWorkflowStoreTest < ActiveSupport::TestCase
  test "loads service config and prompt template from a managed workflow" do
    workflow = build_managed_workflow(
      prompt_template: "Prompt from DB",
      runtime_config: { workspace: { root: "managed-store-root" } }
    )

    store = Symphony::ManagedWorkflowStore.new(workflow.id)

    assert_equal "Prompt from DB", store.prompt_template
    assert_equal "linear", store.service_config.tracker_kind
    assert_equal "managed-store-root", store.service_config.workspace_root
    assert_nil store.last_error
  end

  test "reload_if_changed! refreshes managed workflow config" do
    workflow = build_managed_workflow(
      prompt_template: "Original prompt",
      runtime_config: { workspace: { root: "original-root" } }
    )
    store = Symphony::ManagedWorkflowStore.new(workflow.id)

    workflow.update!(
      prompt_template: "Updated prompt",
      runtime_config: { workspace: { root: "updated-root" } }
    )

    store.reload_if_changed!

    assert_equal "Updated prompt", store.prompt_template
    assert_equal "updated-root", store.service_config.workspace_root
  end

  private
    def build_managed_workflow(prompt_template:, runtime_config:)
      project = Symphony::ManagedProject.create!(name: "Store Project", slug: "store-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Store Linear",
        kind: "linear",
        status: "active",
        config: { project_slug: "STORE" }
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Store Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Store Workflow",
        slug: "store-workflow",
        status: "active",
        prompt_template: prompt_template,
        runtime_config: runtime_config
      )
    end
end
