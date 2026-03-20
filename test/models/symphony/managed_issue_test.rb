require "test_helper"

class Symphony::ManagedIssueTest < ActiveSupport::TestCase
  test "model class exists and binds to managed issues table" do
    assert defined?(Symphony::ManagedIssue), "expected Symphony::ManagedIssue to be defined"
    assert_equal "symphony_managed_issues", Symphony::ManagedIssue.table_name
  end

  test "managed issues table includes planned columns" do
    table_name = :symphony_managed_issues
    connection = ActiveRecord::Base.connection

    assert connection.data_source_exists?(table_name), "expected #{table_name} table to exist"

    columns = connection.columns(table_name).index_by(&:name)
    %w[
      managed_workflow_id identifier title description priority
      state labels blocked_by metadata created_at updated_at
    ].each do |column_name|
      assert_includes columns.keys, column_name
    end
  end

  test "belongs to managed workflow" do
    association = Symphony::ManagedIssue.reflect_on_association(:managed_workflow)

    assert_not_nil association
    assert_equal :belongs_to, association.macro
  end

  test "is valid for database tracker workflows" do
    project = Symphony::ManagedProject.create!(name: "Console", slug: "console-project", status: "active")
    tracker_connection = Symphony::TrackerConnection.create!(name: "Database", kind: "database", status: "active")
    agent_connection = Symphony::AgentConnection.create!(name: "Codex", kind: "codex", status: "active")
    workflow = Symphony::ManagedWorkflow.create!(
      managed_project: project,
      tracker_connection: tracker_connection,
      agent_connection: agent_connection,
      name: "Database Workflow",
      slug: "database-workflow",
      status: "active"
    )

    managed_issue = Symphony::ManagedIssue.new(
      managed_workflow: workflow,
      identifier: "DB-1",
      title: "Database issue"
    )

    assert managed_issue.valid?
  end

  test "rejects workflows without a database tracker connection" do
    project = Symphony::ManagedProject.create!(name: "Platform", slug: "platform-project", status: "active")
    tracker_connection = Symphony::TrackerConnection.create!(name: "Linear", kind: "linear", status: "active")
    agent_connection = Symphony::AgentConnection.create!(name: "Codex", kind: "codex", status: "active")
    workflow = Symphony::ManagedWorkflow.create!(
      managed_project: project,
      tracker_connection: tracker_connection,
      agent_connection: agent_connection,
      name: "Linear Workflow",
      slug: "linear-workflow",
      status: "active"
    )

    managed_issue = Symphony::ManagedIssue.new(
      managed_workflow: workflow,
      identifier: "LIN-1",
      title: "Linear issue"
    )

    assert_not managed_issue.valid?
    assert_includes managed_issue.errors[:managed_workflow], "must use a database tracker connection"
  end
end
