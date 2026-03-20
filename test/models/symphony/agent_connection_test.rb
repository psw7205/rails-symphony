require "test_helper"

class Symphony::AgentConnectionTest < ActiveSupport::TestCase
  test "model class exists" do
    assert defined?(Symphony::AgentConnection), "expected Symphony::AgentConnection to be defined"
  end

  test "model binds to agent connections table" do
    assert_equal "symphony_agent_connections", Symphony::AgentConnection.table_name
  end

  test "agent connections table includes planned columns" do
    table_name = :symphony_agent_connections
    connection = ActiveRecord::Base.connection

    assert connection.data_source_exists?(table_name), "expected #{table_name} table to exist"

    columns = connection.columns(table_name).index_by(&:name)
    %w[name kind status config created_at updated_at].each do |column_name|
      assert_includes columns.keys, column_name
    end
  end

  test "requires name, kind, and status" do
    agent_connection = Symphony::AgentConnection.new

    assert_not agent_connection.valid?
    assert_includes agent_connection.errors[:name], "can't be blank"
    assert_includes agent_connection.errors[:kind], "can't be blank"
    assert_includes agent_connection.errors[:status], "can't be blank"
  end

  test "allows only active or inactive status" do
    active_connection = Symphony::AgentConnection.new(name: "Codex", kind: "codex", status: "active")
    inactive_connection = Symphony::AgentConnection.new(name: "Claude Code", kind: "claude_code", status: "inactive")
    invalid_connection = Symphony::AgentConnection.new(name: "Other", kind: "other", status: "archived")

    assert active_connection.valid?
    assert inactive_connection.valid?
    assert_not invalid_connection.valid?
    assert_includes invalid_connection.errors[:status], "is not included in the list"
  end
end
