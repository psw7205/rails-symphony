require "test_helper"
require "rake"
require "tmpdir"

class Symphony::ImportWorkflowTaskTest < ActiveSupport::TestCase
  setup do
    reset_console_records!
    load_rake_task
  end

  teardown do
    reset_console_records!
  end

  test "imports a legacy workflow file into managed records" do
    workflow_path = write_workflow_file(<<~WORKFLOW)
      ---
      tracker:
        kind: linear
        api_key: $LINEAR_API_KEY
        project_slug: OPS
      agent:
        kind: codex
        max_concurrent_agents: 3
      codex:
        command: bin/codex app-server
      workspace:
        root: imported-workspaces
      polling:
        interval_ms: 45000
      hooks:
        timeout_ms: 120000
      ---
      Imported prompt
    WORKFLOW

    assert_difference("Symphony::ManagedProject.count", 1) do
      assert_difference("Symphony::TrackerConnection.count", 1) do
        assert_difference("Symphony::AgentConnection.count", 1) do
          assert_difference("Symphony::ManagedWorkflow.count", 1) do
            import_task.invoke(workflow_path, "Imported Project", "Imported Workflow")
          end
        end
      end
    end

    project = Symphony::ManagedProject.order(:id).last
    tracker_connection = Symphony::TrackerConnection.order(:id).last
    agent_connection = Symphony::AgentConnection.order(:id).last
    workflow = Symphony::ManagedWorkflow.order(:id).last

    assert_equal "Imported Project", project.name
    assert_equal "imported-project", project.slug

    assert_equal "linear", tracker_connection.kind
    assert_equal(
      {
        "api_key" => "$LINEAR_API_KEY",
        "project_slug" => "OPS"
      },
      tracker_connection.config
    )

    assert_equal "codex", agent_connection.kind
    assert_equal(
      {
        "agent" => { "max_concurrent_agents" => 3 },
        "codex" => { "command" => "bin/codex app-server" }
      },
      agent_connection.config
    )

    assert_equal project.id, workflow.managed_project_id
    assert_equal tracker_connection.id, workflow.tracker_connection_id
    assert_equal agent_connection.id, workflow.agent_connection_id
    assert_equal "Imported Workflow", workflow.name
    assert_equal "imported-workflow", workflow.slug
    assert_equal "Imported prompt", workflow.prompt_template
    assert_equal(
      {
        "workspace" => { "root" => "imported-workspaces" },
        "polling" => { "interval_ms" => 45_000 },
        "hooks" => { "timeout_ms" => 120_000 }
      },
      workflow.runtime_config
    )
  end

  private
    def import_task
      Rake::Task["symphony:import_workflow"].tap(&:reenable)
    end

    def load_rake_task
      return if Rake::Task.task_defined?("symphony:import_workflow")

      Rails.application.load_tasks
    end

    def write_workflow_file(content)
      root = Dir.mktmpdir("workflow_import")
      path = File.join(root, "WORKFLOW.md")
      File.write(path, content)
      path
    end

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
end
