require "test_helper"

class Symphony::TrackerConnectionTest < ActiveSupport::TestCase
  test "model class exists" do
    assert defined?(Symphony::TrackerConnection), "expected Symphony::TrackerConnection to be defined"
  end

  test "model binds to tracker connections table" do
    assert_equal "symphony_tracker_connections", Symphony::TrackerConnection.table_name
  end

  test "tracker connections table includes planned columns" do
    table_name = :symphony_tracker_connections
    connection = ActiveRecord::Base.connection

    assert connection.data_source_exists?(table_name), "expected #{table_name} table to exist"

    columns = connection.columns(table_name).index_by(&:name)
    %w[name kind status config created_at updated_at].each do |column_name|
      assert_includes columns.keys, column_name
    end
  end

  test "requires name, kind, and status" do
    tracker_connection = Symphony::TrackerConnection.new

    assert_not tracker_connection.valid?
    assert_includes tracker_connection.errors[:name], "can't be blank"
    assert_includes tracker_connection.errors[:kind], "can't be blank"
    assert_includes tracker_connection.errors[:status], "can't be blank"
  end

  test "allows only active or inactive status" do
    active_connection = Symphony::TrackerConnection.new(name: "Linear", kind: "linear", status: "active")
    inactive_connection = Symphony::TrackerConnection.new(name: "GitHub", kind: "github", status: "inactive")
    invalid_connection = Symphony::TrackerConnection.new(name: "Database", kind: "database", status: "archived")

    assert active_connection.valid?
    assert inactive_connection.valid?
    assert_not invalid_connection.valid?
    assert_includes invalid_connection.errors[:status], "is not included in the list"
  end
end
