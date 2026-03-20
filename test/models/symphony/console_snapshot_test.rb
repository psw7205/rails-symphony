require "test_helper"

class Symphony::ConsoleSnapshotTest < ActiveSupport::TestCase
  test "build aggregates active managed workflow rows" do
    Symphony::WorkflowRuntimeManager.clear!
    first_workflow = build_managed_workflow(
      slug: "console-workflow-one",
      name: "Console Workflow One"
    )
    second_workflow = build_managed_workflow(
      slug: "console-workflow-two",
      name: "Console Workflow Two"
    )

    snapshot = Symphony::ConsoleSnapshot.build

    assert_operator snapshot[:project_count], :>=, 2
    assert_operator snapshot[:active_workflow_count], :>=, 2
    assert_operator snapshot[:workflow_rows].size, :>=, 2
    workflow_ids = snapshot[:workflow_rows].map { |row| row[:managed_workflow].id }
    assert_includes workflow_ids, first_workflow.id
    assert_includes workflow_ids, second_workflow.id
    assert_equal 0, snapshot[:totals][:running]
    assert_equal 0, snapshot[:totals][:retrying]
  ensure
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "build aggregates running totals across managed workflows" do
    Symphony::WorkflowRuntimeManager.clear!
    workflow = build_managed_workflow(
      slug: "console-running-workflow",
      name: "Console Running Workflow"
    )
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "console-running-1", identifier: "CR-1", title: "Console running", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick

    snapshot = Symphony::ConsoleSnapshot.build

    assert_equal 1, snapshot[:totals][:running]
    assert_equal 0, snapshot[:totals][:retrying]
  ensure
    Symphony::WorkflowRuntimeManager.clear!
  end

  private
    def build_managed_workflow(slug:, name:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "#{name} Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "#{name} Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: "active",
        prompt_template: "Console prompt",
        runtime_config: { workspace: { root: "console-workspaces" } }
      )
    end
end
