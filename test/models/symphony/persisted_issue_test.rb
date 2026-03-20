require "test_helper"

class Symphony::PersistedIssueTest < ActiveSupport::TestCase
  test "belongs to managed workflow" do
    association = Symphony::PersistedIssue.reflect_on_association(:managed_workflow)

    assert_not_nil association
    assert_equal :belongs_to, association.macro
  end

  test "persisted issues table includes workflow scope columns" do
    connection = ActiveRecord::Base.connection
    columns = connection.columns(:symphony_issues).index_by(&:name)

    %w[managed_workflow_id source_issue_id tracker_kind].each do |column_name|
      assert_includes columns.keys, column_name
    end
  end

  test "persisted issues use a workflow scoped unique source issue index" do
    connection = ActiveRecord::Base.connection

    scoped_index = connection.indexes(:symphony_issues).find do |index|
      index.columns == [ "managed_workflow_id", "source_issue_id" ]
    end
    identifier_index = connection.indexes(:symphony_issues).find do |index|
      index.columns == [ "identifier" ]
    end

    assert scoped_index&.unique, "expected a unique index on managed_workflow_id and source_issue_id"
    assert_not identifier_index&.unique, "expected identifier to stop being globally unique"
  end

  test "runtime support tables include managed workflow scope columns" do
    connection = ActiveRecord::Base.connection

    {
      symphony_run_attempts: "managed_workflow_id",
      symphony_retry_entries: "managed_workflow_id",
      symphony_orchestrator_states: "managed_workflow_id"
    }.each do |table_name, column_name|
      columns = connection.columns(table_name).index_by(&:name)
      assert_includes columns.keys, column_name, "expected #{table_name} to include #{column_name}"
    end
  end

  test "allows the same source issue id in different workflows" do
    first_workflow, second_workflow = build_managed_workflows

    first_issue = Symphony::PersistedIssue.new(
      id: "runtime-1",
      managed_workflow_id: first_workflow.id,
      source_issue_id: "shared-source-id",
      tracker_kind: "linear",
      identifier: "MT-1",
      state: "In Progress"
    )

    second_issue = Symphony::PersistedIssue.new(
      id: "runtime-2",
      managed_workflow_id: second_workflow.id,
      source_issue_id: "shared-source-id",
      tracker_kind: "linear",
      identifier: "MT-2",
      state: "Todo"
    )

    assert first_issue.valid?
    assert second_issue.valid?
  end

  test "rejects duplicate source issue ids within the same workflow" do
    workflow, = build_managed_workflows

    Symphony::PersistedIssue.create!(
      id: "runtime-3",
      managed_workflow_id: workflow.id,
      source_issue_id: "workflow-source-id",
      tracker_kind: "linear",
      identifier: "MT-3",
      state: "In Progress"
    )

    duplicate_issue = Symphony::PersistedIssue.new(
      id: "runtime-4",
      managed_workflow_id: workflow.id,
      source_issue_id: "workflow-source-id",
      tracker_kind: "linear",
      identifier: "MT-4",
      state: "Todo"
    )

    assert_not duplicate_issue.valid?
    assert_includes duplicate_issue.errors[:source_issue_id], "has already been taken"
  end

  private
    def build_managed_workflows
      project = Symphony::ManagedProject.create!(name: "Runtime Project", slug: "runtime-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "Linear", kind: "linear", status: "active")
      agent_connection = Symphony::AgentConnection.create!(name: "Codex", kind: "codex", status: "active")

      [
        Symphony::ManagedWorkflow.create!(
          managed_project: project,
          tracker_connection: tracker_connection,
          agent_connection: agent_connection,
          name: "Runtime One",
          slug: "runtime-one",
          status: "active"
        ),
        Symphony::ManagedWorkflow.create!(
          managed_project: project,
          tracker_connection: tracker_connection,
          agent_connection: agent_connection,
          name: "Runtime Two",
          slug: "runtime-two",
          status: "active"
        )
      ]
    end
end
