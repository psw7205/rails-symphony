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

  test "build aggregates running entries across managed workflows" do
    Symphony::WorkflowRuntimeManager.clear!
    workflow = build_managed_workflow(
      slug: "console-running-entry-workflow",
      name: "Console Running Entry Workflow"
    )
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "console-running-entry-1", identifier: "CRE-1", title: "Console running entry", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick

    snapshot = Symphony::ConsoleSnapshot.build

    assert_equal "CRE-1", snapshot[:running].first[:issue_identifier]
    assert_equal workflow.id, snapshot[:running].first[:managed_workflow_id]
  ensure
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "build aggregates codex token and runtime totals across managed workflows" do
    Symphony::WorkflowRuntimeManager.clear!
    first_workflow = build_managed_workflow(
      slug: "console-totals-workflow-one",
      name: "Console Totals Workflow One"
    )
    second_workflow = build_managed_workflow(
      slug: "console-totals-workflow-two",
      name: "Console Totals Workflow Two"
    )

    first_context = Symphony::WorkflowRuntimeManager.fetch(first_workflow.id)
    second_context = Symphony::WorkflowRuntimeManager.fetch(second_workflow.id)

    first_context.orchestrator.instance_variable_get(:@codex_totals).merge!(
      input_tokens: 100,
      output_tokens: 40,
      total_tokens: 140,
      seconds_running: 120.0
    )
    second_context.orchestrator.instance_variable_get(:@codex_totals).merge!(
      input_tokens: 30,
      output_tokens: 10,
      total_tokens: 40,
      seconds_running: 60.0
    )

    snapshot = Symphony::ConsoleSnapshot.build

    assert_equal 130, snapshot[:codex_totals][:input_tokens]
    assert_equal 50, snapshot[:codex_totals][:output_tokens]
    assert_equal 180, snapshot[:codex_totals][:total_tokens]
    assert_in_delta 180.0, snapshot[:codex_totals][:seconds_running], 0.01
  ensure
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "build aggregates rate limits by workflow slug" do
    Symphony::WorkflowRuntimeManager.clear!
    workflow = build_managed_workflow(
      slug: "console-rate-limit-workflow",
      name: "Console Rate Limit Workflow"
    )
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.instance_variable_set(
      :@codex_rate_limits,
      { "remaining" => 42, "reset_at" => "2026-03-20T12:00:00Z" }
    )

    snapshot = Symphony::ConsoleSnapshot.build

    assert_equal 42, snapshot[:rate_limits][workflow.slug]["remaining"]
  ensure
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "build exposes recent failures from retry entries" do
    Symphony::WorkflowRuntimeManager.clear!
    workflow = build_managed_workflow(
      slug: "console-failure-workflow",
      name: "Console Failure Workflow"
    )
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "console-failure-1", identifier: "CF-1", title: "Console failure", state: "In Progress", priority: 1, created_at: Time.now)
    )
    context.orchestrator.tick
    context.orchestrator.on_worker_exit_abnormal("console-failure-1", "CF-1", attempt: 1, error: "process_died")

    snapshot = Symphony::ConsoleSnapshot.build

    assert_equal "CF-1", snapshot[:recent_failures].first[:issue_identifier]
    assert_equal "process_died", snapshot[:recent_failures].first[:error]
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
