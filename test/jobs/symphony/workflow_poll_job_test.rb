require "test_helper"

class Symphony::WorkflowPollJobTest < ActiveJob::TestCase
  setup do
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "perform triggers a workflow specific orchestrator tick" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "workflow-poll-1", identifier: "WP-1", title: "Workflow poll issue", state: "In Progress", priority: 1, created_at: Time.now)
    )

    Symphony::WorkflowPollJob.perform_now(workflow_id: workflow.id)

    snapshot = context.orchestrator.snapshot
    assert_equal 1, snapshot[:counts][:running]
    assert_equal "WP-1", snapshot[:running].first[:issue_identifier]
  end

  private
    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "Workflow Poll Project", slug: "workflow-poll-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Workflow Poll Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Workflow Poll Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Workflow Poll Workflow",
        slug: "workflow-poll-workflow",
        status: "active",
        prompt_template: "Workflow poll prompt",
        runtime_config: { workspace: { root: "workflow-poll-workspaces" } }
      )
    end
end
