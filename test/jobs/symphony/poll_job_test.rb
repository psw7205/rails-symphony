require "test_helper"

class Symphony::PollJobTest < ActiveJob::TestCase
  setup do
    clear_enqueued_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  teardown do
    clear_enqueued_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
    Symphony.orchestrator = nil
  end

  test "perform enqueues workflow poll jobs for active managed workflows" do
    active_workflow = build_managed_workflow(slug: "poll-active-workflow", name: "Poll Active Workflow", status: "active")
    build_managed_workflow(slug: "poll-inactive-workflow", name: "Poll Inactive Workflow", status: "inactive")

    assert_enqueued_with(job: Symphony::WorkflowPollJob, args: [ { workflow_id: active_workflow.id } ]) do
      Symphony::PollJob.perform_now
    end

    assert_equal 1, enqueued_jobs.count { |job| job[:job] == Symphony::WorkflowPollJob }
  end

  test "perform still ticks the legacy orchestrator when present" do
    tick_count = 0
    Symphony.orchestrator = Object.new.tap do |orchestrator|
      orchestrator.define_singleton_method(:tick) { tick_count += 1 }
    end

    Symphony::PollJob.perform_now

    assert_equal 1, tick_count
  end

  private
    def build_managed_workflow(slug:, name:, status:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "#{name} Tracker",
        kind: "memory",
        status: "active",
        config: {}
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "#{name} Agent",
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
        status: status,
        prompt_template: "Poll job prompt",
        runtime_config: { workspace: { root: "poll-job-workspaces" } }
      )
    end

    def reset_console_records!
      Symphony::RunAttempt.delete_all
      Symphony::RetryEntry.delete_all
      Symphony::PersistedIssue.delete_all
      Symphony::OrchestratorState.delete_all
      Symphony::ManagedIssue.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end
end
