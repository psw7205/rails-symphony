require "test_helper"

class Symphony::ManagedWorkflowTest < ActiveSupport::TestCase
  test "model class exists" do
    assert defined?(Symphony::ManagedWorkflow), "expected Symphony::ManagedWorkflow to be defined"
  end

  test "model binds to managed workflows table" do
    assert defined?(Symphony::ManagedWorkflow), "expected Symphony::ManagedWorkflow to be defined"
    assert_equal "symphony_managed_workflows", Symphony::ManagedWorkflow.table_name
  end

  test "managed workflows table includes planned columns" do
    table_name = :symphony_managed_workflows
    connection = ActiveRecord::Base.connection

    assert connection.data_source_exists?(table_name), "expected #{table_name} table to exist"

    columns = connection.columns(table_name).index_by(&:name)
    %w[
      managed_project_id tracker_connection_id agent_connection_id
      name slug status prompt_template runtime_config created_at updated_at
    ].each do |column_name|
      assert_includes columns.keys, column_name
    end
  end
end
