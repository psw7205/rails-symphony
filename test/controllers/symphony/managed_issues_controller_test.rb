require "test_helper"

class Symphony::ManagedIssuesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    reset_console_records!
    Symphony::WorkflowRuntimeManager.clear!
  end

  teardown do
    clear_enqueued_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  test "GET /workflows/:workflow_id/issues renders managed issues for database workflows" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-workflow", name: "Managed Issues Workflow")
    Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-1",
      title: "Managed issue one",
      state: "Todo"
    )

    get "/workflows/#{workflow.id}/issues"
    assert_response :success
    assert_includes response.body, "MI-1"
    assert_includes response.body, "Managed issue one"
  end

  test "GET /workflows/:workflow_id/issues renders managed issue CRUD actions" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-actions-workflow", name: "Managed Issues Actions Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-ACTIONS-1",
      title: "Managed issue actions",
      state: "Todo"
    )

    get "/workflows/#{workflow.id}/issues"

    assert_response :success
    assert_includes response.body, "/workflows/#{workflow.id}/issues/new"
    assert_includes response.body, "/workflows/#{workflow.id}/issues/#{issue.id}/edit"
    assert_includes response.body, "/workflows/#{workflow.id}/issues/#{issue.id}"
  end

  test "GET /workflows/:workflow_id/issues renders a read-only issue screen for non-database workflows" do
    workflow = build_managed_workflow(tracker_kind: "memory", slug: "non-database-workflow", name: "Non Database Workflow")
    context = Symphony::WorkflowRuntimeManager.fetch(workflow.id)
    context.tracker.add_issue(
      Symphony::Issue.new(
        id: "memory-read-only-1",
        identifier: "RO-1",
        title: "Read only issue",
        state: "In Progress",
        priority: 1,
        created_at: Time.current
      )
    )

    get "/workflows/#{workflow.id}/issues"

    assert_response :success
    assert_includes response.body, "RO-1"
    assert_includes response.body, "Read only issue"
    refute_includes response.body, "/workflows/#{workflow.id}/issues/new"
    refute_includes response.body, "Delete"
  end

  test "GET /workflows/:workflow_id/issues/new renders the managed issue form" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-new-workflow", name: "Managed Issues New Workflow")

    get "/workflows/#{workflow.id}/issues/new"
    assert_response :success
    assert_includes response.body, "New managed issue"
  end

  test "POST /workflows/:workflow_id/issues creates a managed issue" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-create-workflow", name: "Managed Issues Create Workflow")

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      post "/workflows/#{workflow.id}/issues", params: {
        managed_issue: {
          identifier: "MI-2",
          title: "Created managed issue",
          description: "Created from controller test",
          priority: "1",
          state: "Todo"
        }
      }
    end

    issue = Symphony::ManagedIssue.order(:id).last
    trigger_event = Symphony::WorkflowTriggerEvent.order(:id).last
    job = enqueued_jobs.last
    assert_redirected_to "/workflows/#{workflow.id}/issues"
    assert_equal "MI-2", issue.identifier
    assert_equal workflow.id, issue.managed_workflow_id
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "database_write", trigger_event.source
    assert_equal "enqueued", trigger_event.status
    assert_equal workflow.id, job[:args].first["workflow_id"]
    assert_equal trigger_event.id, job[:args].first["trigger_event_id"]
  end

  test "POST /workflows/:workflow_id/issues renders validation errors" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-invalid-workflow", name: "Managed Issues Invalid Workflow")

    post "/workflows/#{workflow.id}/issues", params: {
      managed_issue: {
        identifier: "",
        title: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Identifier can&#39;t be blank"
  end

  test "POST /workflows/:workflow_id/issues returns 404 for non-database workflows" do
    workflow = build_managed_workflow(tracker_kind: "memory", slug: "managed-issues-create-non-database-workflow", name: "Managed Issues Create Non Database Workflow")

    assert_no_difference("Symphony::ManagedIssue.count") do
      post "/workflows/#{workflow.id}/issues", params: {
        managed_issue: {
          identifier: "MI-NON-DB-1",
          title: "Should not be created",
          state: "Todo"
        }
      }
    end

    assert_response :not_found
  end

  test "GET /workflows/:workflow_id/issues/:id/edit renders the managed issue form" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-edit-workflow", name: "Managed Issues Edit Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-EDIT-1",
      title: "Editable managed issue",
      state: "Todo"
    )

    get "/workflows/#{workflow.id}/issues/#{issue.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit managed issue"
    assert_includes response.body, "Editable managed issue"
  end

  test "PATCH /workflows/:workflow_id/issues/:id updates a managed issue" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-update-workflow", name: "Managed Issues Update Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-UPDATE-1",
      title: "Editable managed issue",
      state: "Todo"
    )

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      patch "/workflows/#{workflow.id}/issues/#{issue.id}", params: {
        managed_issue: {
          identifier: "MI-UPDATE-1",
          title: "Updated managed issue",
          description: "Updated from controller test",
          priority: "2",
          state: "In Progress"
        }
      }
    end

    trigger_event = Symphony::WorkflowTriggerEvent.order(:id).last
    job = enqueued_jobs.last
    assert_redirected_to "/workflows/#{workflow.id}/issues"
    issue.reload
    assert_equal "Updated managed issue", issue.title
    assert_equal "In Progress", issue.state
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "database_write", trigger_event.source
    assert_equal "enqueued", trigger_event.status
    assert_equal workflow.id, job[:args].first["workflow_id"]
    assert_equal trigger_event.id, job[:args].first["trigger_event_id"]
  end

  test "PATCH /workflows/:workflow_id/issues/:id renders validation errors" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-invalid-update-workflow", name: "Managed Issues Invalid Update Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-INVALID-1",
      title: "Editable managed issue",
      state: "Todo"
    )

    patch "/workflows/#{workflow.id}/issues/#{issue.id}", params: {
      managed_issue: {
        identifier: "",
        title: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Identifier can&#39;t be blank"
  end

  test "PATCH /workflows/:workflow_id/issues/:id returns 404 for issues outside the workflow" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-scoped-update-workflow", name: "Managed Issues Scoped Update Workflow")
    other_workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-scoped-update-other-workflow", name: "Managed Issues Scoped Update Other Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: other_workflow,
      identifier: "MI-SCOPED-UPDATE-1",
      title: "Scoped managed issue",
      state: "Todo"
    )

    patch "/workflows/#{workflow.id}/issues/#{issue.id}", params: {
      managed_issue: {
        identifier: "MI-SCOPED-UPDATE-1",
        title: "Updated from wrong workflow"
      }
    }

    assert_response :not_found
    assert_equal "Scoped managed issue", issue.reload.title
  end

  test "PATCH /workflows/:workflow_id/issues/:id returns 404 for non-database workflows" do
    workflow = build_managed_workflow(tracker_kind: "memory", slug: "managed-issues-update-non-database-workflow", name: "Managed Issues Update Non Database Workflow")
    issue_workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-update-database-workflow", name: "Managed Issues Update Database Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: issue_workflow,
      identifier: "MI-NON-DB-UPDATE-1",
      title: "Should stay unchanged",
      state: "Todo"
    )

    patch "/workflows/#{workflow.id}/issues/#{issue.id}", params: {
      managed_issue: {
        identifier: "MI-NON-DB-UPDATE-1",
        title: "Updated from wrong tracker kind"
      }
    }

    assert_response :not_found
    assert_equal "Should stay unchanged", issue.reload.title
  end

  test "DELETE /workflows/:workflow_id/issues/:id destroys a managed issue" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-destroy-workflow", name: "Managed Issues Destroy Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: workflow,
      identifier: "MI-DELETE-1",
      title: "Deletable managed issue",
      state: "Todo"
    )

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      delete "/workflows/#{workflow.id}/issues/#{issue.id}"
    end

    trigger_event = Symphony::WorkflowTriggerEvent.order(:id).last
    job = enqueued_jobs.last
    assert_redirected_to "/workflows/#{workflow.id}/issues"
    assert_nil Symphony::ManagedIssue.find_by(id: issue.id)
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "database_write", trigger_event.source
    assert_equal "enqueued", trigger_event.status
    assert_equal workflow.id, job[:args].first["workflow_id"]
    assert_equal trigger_event.id, job[:args].first["trigger_event_id"]
  end

  test "DELETE /workflows/:workflow_id/issues/:id returns 404 for issues outside the workflow" do
    workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-scoped-destroy-workflow", name: "Managed Issues Scoped Destroy Workflow")
    other_workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-scoped-destroy-other-workflow", name: "Managed Issues Scoped Destroy Other Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: other_workflow,
      identifier: "MI-SCOPED-DELETE-1",
      title: "Scoped managed issue",
      state: "Todo"
    )

    delete "/workflows/#{workflow.id}/issues/#{issue.id}"

    assert_response :not_found
    assert_equal issue.id, issue.reload.id
  end

  test "DELETE /workflows/:workflow_id/issues/:id returns 404 for non-database workflows" do
    workflow = build_managed_workflow(tracker_kind: "memory", slug: "managed-issues-destroy-non-database-workflow", name: "Managed Issues Destroy Non Database Workflow")
    issue_workflow = build_managed_workflow(tracker_kind: "database", slug: "managed-issues-destroy-database-workflow", name: "Managed Issues Destroy Database Workflow")
    issue = Symphony::ManagedIssue.create!(
      managed_workflow: issue_workflow,
      identifier: "MI-NON-DB-DELETE-1",
      title: "Should stay present",
      state: "Todo"
    )

    assert_no_difference("Symphony::ManagedIssue.count") do
      delete "/workflows/#{workflow.id}/issues/#{issue.id}"
    end

    assert_response :not_found
  end

  private
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

    def build_managed_workflow(tracker_kind:, slug:, name:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "#{name} Tracker", kind: tracker_kind, status: "active", config: {})
      agent_connection = Symphony::AgentConnection.create!(name: "#{name} Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: "active"
      )
    end
end
