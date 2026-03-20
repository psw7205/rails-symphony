require "test_helper"

class Symphony::AgentWorkerJobTest < ActiveJob::TestCase
  setup do
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    Symphony::WorkflowRuntimeManager.clear!
  end

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

  test "perform uses the workflow runtime context when managed workflow id is given" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    captured_runner_args = []
    fake_runner = Object.new
    fake_runner.define_singleton_method(:run) do |issue:, attempt:|
      { ok: true }
    end
    runner_singleton = class << Symphony::AgentRunner; self; end
    runner_singleton.alias_method :__managed_worker_test_new, :new
    runner_singleton.define_method(:new) do |**kwargs|
      captured_runner_args << kwargs
      fake_runner
    end

    Symphony.tracker = nil
    Symphony.workspace = nil
    Symphony.agent = nil
    Symphony.workflow_store = nil
    Symphony.orchestrator = nil

    Symphony::AgentWorkerJob.perform_now(
      issue_id: "managed-perform-1",
      issue_identifier: "MW-PERFORM-1",
      issue_title: "Managed perform issue",
      issue_state: "In Progress",
      managed_workflow_id: workflow.id
    )

    runner_args = captured_runner_args.fetch(0)
    assert_same context.tracker, runner_args[:tracker]
    assert_same context.workspace, runner_args[:workspace]
    assert_same context.agent, runner_args[:agent]
    assert_equal context.workflow_store.service_config.tracker_kind, runner_args[:config].tracker_kind
    assert_equal context.workflow_store.service_config.workspace_root, runner_args[:config].workspace_root
    assert_equal context.workflow_store.prompt_template, runner_args[:prompt_template]
  ensure
    Symphony.tracker = nil
    Symphony.workspace = nil
    Symphony.agent = nil
    Symphony.workflow_store = nil
    Symphony.orchestrator = nil
    if defined?(runner_singleton) && runner_singleton.method_defined?(:__managed_worker_test_new)
      runner_singleton.alias_method :new, :__managed_worker_test_new
      runner_singleton.remove_method :__managed_worker_test_new
    end
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
