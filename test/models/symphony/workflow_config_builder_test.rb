require "test_helper"

class Symphony::WorkflowConfigBuilderTest < ActiveSupport::TestCase
  test "builds a service config hash from managed workflow records" do
    project = Symphony::ManagedProject.create!(name: "Builder Project", slug: "builder-project", status: "active")
    tracker_connection = Symphony::TrackerConnection.create!(
      name: "Linear Builder",
      kind: "linear",
      status: "active",
      config: {
        endpoint: "https://linear.example/graphql",
        project_slug: "OPS"
      }
    )
    agent_connection = Symphony::AgentConnection.create!(
      name: "Codex Builder",
      kind: "codex",
      status: "active",
      config: {
        agent: { max_concurrent_agents: 4 },
        codex: { command: "bin/codex app-server" }
      }
    )
    workflow = Symphony::ManagedWorkflow.create!(
      managed_project: project,
      tracker_connection: tracker_connection,
      agent_connection: agent_connection,
      name: "Builder Workflow",
      slug: "builder-workflow",
      status: "active",
      prompt_template: "Prompt from DB",
      runtime_config: {
        workspace: { root: "managed-workspaces" },
        agent: { max_concurrent_agents: 7 }
      }
    )

    service_config = Symphony::ServiceConfig.new(Symphony::WorkflowConfigBuilder.build(workflow))

    assert_equal "linear", service_config.tracker_kind
    assert_equal "https://linear.example/graphql", service_config.tracker_endpoint
    assert_equal "OPS", service_config.tracker_project_slug
    assert_equal "managed-workspaces", service_config.workspace_root
    assert_equal 7, service_config.max_concurrent_agents
    assert_equal "bin/codex app-server", service_config.codex_command
  end
end
