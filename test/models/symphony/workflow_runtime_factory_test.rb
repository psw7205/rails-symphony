require "test_helper"

class Symphony::WorkflowRuntimeFactoryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "build creates a runtime context for a managed workflow" do
    workflow = build_managed_workflow

    context = Symphony::WorkflowRuntimeFactory.build(workflow.id)

    assert_equal workflow.id, context.managed_workflow.id
    assert_instance_of Symphony::Trackers::Memory, context.tracker
    assert_instance_of Symphony::Workspace, context.workspace
    assert_instance_of Symphony::Agents::Codex, context.agent
    assert_instance_of Symphony::ManagedWorkflowStore, context.workflow_store
    assert_instance_of Symphony::Orchestrator, context.orchestrator
    assert_equal workflow.id, context.orchestrator.managed_workflow_id
    assert_equal 0, context.orchestrator.snapshot[:counts][:running]
  end

  test "build creates a database tracker runtime context for database workflows" do
    workflow = build_managed_workflow(
      slug: "database-runtime-factory-workflow",
      name: "Database Runtime Factory Workflow",
      tracker_kind: "database"
    )

    context = Symphony::WorkflowRuntimeFactory.build(workflow.id)

    assert_instance_of Symphony::Trackers::Database, context.tracker
  end

  test "build creates a github tracker runtime context for github workflows" do
    workflow = build_managed_workflow(
      slug: "github-runtime-factory-workflow",
      name: "GitHub Runtime Factory Workflow",
      tracker_kind: "github",
      tracker_config: {
        repo: "owner/repo",
        api_key: "ghp_test"
      }
    )

    context = Symphony::WorkflowRuntimeFactory.build(workflow.id)

    assert_instance_of Symphony::Trackers::GithubIssues, context.tracker
  end

  test "managed runtime dispatch enqueues an agent worker job with workflow id" do
    workflow = build_managed_workflow
    context = Symphony::WorkflowRuntimeFactory.build(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(id: "dispatch-1", identifier: "WD-1", title: "Dispatch test", state: "In Progress", priority: 1, created_at: Time.now)
    )

    assert_enqueued_with(
      job: Symphony::AgentWorkerJob,
      args: [ {
        issue_id: "dispatch-1",
        issue_identifier: "WD-1",
        issue_title: "Dispatch test",
        issue_state: "In Progress",
        attempt: nil,
        managed_workflow_id: workflow.id
      } ]
    ) do
      context.orchestrator.tick
    end
  end

  private
    def build_managed_workflow(slug: "runtime-factory-workflow", name: "Runtime Factory Workflow", tracker_kind: "memory", tracker_config: {})
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "#{name} Tracker",
        kind: tracker_kind,
        status: "active",
        config: tracker_config
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "#{name} Codex",
        kind: "codex",
        status: "active",
        config: {
          codex: { command: "bin/codex app-server" }
        }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: "active",
        prompt_template: "Prompt from runtime factory",
        runtime_config: {
          workspace: { root: "runtime-factory-workspaces" }
        }
      )
    end
end
