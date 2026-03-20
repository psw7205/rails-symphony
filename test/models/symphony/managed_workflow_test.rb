require "test_helper"

class Symphony::ManagedWorkflowTest < ActiveSupport::TestCase
  test "model class exists" do
    assert defined?(Symphony::ManagedWorkflow), "expected Symphony::ManagedWorkflow to be defined"
  end

  test "model binds to managed workflows table" do
    assert defined?(Symphony::ManagedWorkflow), "expected Symphony::ManagedWorkflow to be defined"
    assert_equal "symphony_managed_workflows", Symphony::ManagedWorkflow.table_name
  end

  test "belongs to managed project, tracker connection, and agent connection" do
    managed_project = Symphony::ManagedWorkflow.reflect_on_association(:managed_project)
    tracker_connection = Symphony::ManagedWorkflow.reflect_on_association(:tracker_connection)
    agent_connection = Symphony::ManagedWorkflow.reflect_on_association(:agent_connection)

    assert_not_nil managed_project
    assert_equal :belongs_to, managed_project.macro

    assert_not_nil tracker_connection
    assert_equal :belongs_to, tracker_connection.macro

    assert_not_nil agent_connection
    assert_equal :belongs_to, agent_connection.macro
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

  test "requires managed project, tracker connection, and agent connection" do
    workflow = Symphony::ManagedWorkflow.new(name: "Console", slug: "console", status: "active")

    assert_not workflow.valid?
    assert_includes workflow.errors[:managed_project], "must exist"
    assert_includes workflow.errors[:tracker_connection], "must exist"
    assert_includes workflow.errors[:agent_connection], "must exist"
  end
end
