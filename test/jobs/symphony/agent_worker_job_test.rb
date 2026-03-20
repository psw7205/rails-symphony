require "test_helper"

class Symphony::AgentWorkerJobTest < ActiveJob::TestCase
  test "restore_issue reads a managed persisted issue by workflow scoped runtime id" do
    workflow = build_managed_workflow
    Symphony::PersistedIssue.create!(
      id: "#{workflow.id}:managed-issue-1",
      managed_workflow_id: workflow.id,
      source_issue_id: "managed-issue-1",
      tracker_kind: "memory",
      identifier: "MW-RESTORE-1",
      title: "Managed restore issue",
      state: "In Progress"
    )

    issue = Symphony::AgentWorkerJob.new.send(
      :restore_issue,
      "managed-issue-1",
      "MW-RESTORE-1",
      "Managed restore issue",
      "In Progress",
      workflow.id
    )

    assert_equal "managed-issue-1", issue.id
    assert_equal "MW-RESTORE-1", issue.identifier
    assert_equal "Managed restore issue", issue.title
    assert_equal "In Progress", issue.state
  end

  private
    def build_managed_workflow
      project = Symphony::ManagedProject.create!(name: "Agent Worker Project", slug: "agent-worker-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Agent Worker Memory",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Agent Worker Codex",
        kind: "codex",
        status: "active",
        config: { codex: { command: "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Agent Worker Workflow",
        slug: "agent-worker-workflow",
        status: "active",
        prompt_template: "Agent worker prompt",
        runtime_config: { workspace: { root: "agent-worker-workspaces" } }
      )
    end
end
