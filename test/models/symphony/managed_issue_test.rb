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
end
