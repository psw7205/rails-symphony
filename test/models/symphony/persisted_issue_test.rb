require "test_helper"

class Symphony::PersistedIssueTest < ActiveSupport::TestCase
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
end
