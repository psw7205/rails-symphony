require "test_helper"

class Symphony::WorkflowPollJobTest < ActiveJob::TestCase
  setup do
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    Symphony::WorkflowRuntimeManager.clear!
  end

  test "perform runs the workflow tick and updates trigger summary on success" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "workflow-poll-1", identifier: "WP-1", title: "Workflow poll issue", state: "In Progress", priority: 1, created_at: Time.now)
    )
    trigger_event = Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "poll",
      status: "enqueued",
      signature_state: "not_applicable",
      requested_at: Time.current
    )

    Symphony::WorkflowPollJob.perform_now(workflow_id: workflow.id, trigger_event_id: trigger_event.id)

    snapshot = context.orchestrator.snapshot
    trigger_event.reload
    orchestrator_state = Symphony::OrchestratorState.for_workflow!(workflow.id)

    assert_equal 1, snapshot[:counts][:running]
    assert_equal "WP-1", snapshot[:running].first[:issue_identifier]
    assert_equal "succeeded", trigger_event.status
    assert_not_nil trigger_event.started_at
    assert_not_nil trigger_event.finished_at
    assert_equal "poll", orchestrator_state.last_trigger_source
    assert_equal "succeeded", orchestrator_state.last_tick_status
    assert_equal trigger_event.id, orchestrator_state.last_workflow_trigger_event_id
  end

  test "perform records trigger failure summary when the workflow tick reports failure" do
    workflow = build_managed_workflow
    trigger_event = Symphony::WorkflowTriggerEvent.create!(
      managed_workflow: workflow,
      source: "manual_refresh",
      status: "enqueued",
      signature_state: "not_applicable",
      requested_at: Time.current
    )
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.orchestrator.define_singleton_method(:tick) do
      { ok: false, error: "tick_failed" }
    end

    Symphony::WorkflowPollJob.perform_now(workflow_id: workflow.id, trigger_event_id: trigger_event.id)

    trigger_event.reload
    orchestrator_state = Symphony::OrchestratorState.for_workflow!(workflow.id)

    assert_equal "failed", trigger_event.status
    assert_equal "tick_failed", trigger_event.error
    assert_equal "failed", orchestrator_state.last_tick_status
    assert_equal "tick_failed", orchestrator_state.last_tick_error
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
