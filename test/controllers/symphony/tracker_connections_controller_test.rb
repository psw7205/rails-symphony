require "test_helper"

class Symphony::TrackerConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
  end

  teardown do
    reset_console_records!
  end

  test "GET /tracker_connections/new renders the tracker connection form" do
    get "/tracker_connections/new"
    assert_response :success
    assert_includes response.body, "New tracker connection"
  end

  test "POST /tracker_connections creates a tracker connection" do
    post "/tracker_connections", params: {
      tracker_connection: {
        name: "Linear Connection",
        kind: "linear",
        status: "active",
        config_json: "{\"project_slug\":\"OPS\"}"
      }
    }

    connection = Symphony::TrackerConnection.order(:id).last
    assert_redirected_to "/projects"
    assert_equal "Linear Connection", connection.name
    assert_equal "OPS", connection.config["project_slug"]
  end

  test "POST /tracker_connections renders validation errors" do
    post "/tracker_connections", params: {
      tracker_connection: {
        name: "",
        kind: "",
        status: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Name can&#39;t be blank"
  end

  test "GET /tracker_connections/:id/edit renders the tracker connection form" do
    tracker_connection = Symphony::TrackerConnection.create!(
      name: "Editable Linear Connection",
      kind: "linear",
      status: "active",
      config: { "project_slug" => "OPS" }
    )

    get "/tracker_connections/#{tracker_connection.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit tracker connection"
    assert_includes response.body, "Editable Linear Connection"
  end

  test "PATCH /tracker_connections/:id updates a tracker connection" do
    tracker_connection = Symphony::TrackerConnection.create!(
      name: "Editable Linear Connection",
      kind: "linear",
      status: "active",
      config: { "project_slug" => "OPS" }
    )

    patch "/tracker_connections/#{tracker_connection.id}", params: {
      tracker_connection: {
        name: "Updated Database Connection",
        kind: "database",
        status: "inactive",
        config_json: "{\"table\":\"symphony_managed_issues\"}"
      }
    }

    assert_redirected_to "/projects"
    tracker_connection.reload
    assert_equal "Updated Database Connection", tracker_connection.name
    assert_equal "database", tracker_connection.kind
    assert_equal "inactive", tracker_connection.status
    assert_equal "symphony_managed_issues", tracker_connection.config["table"]
  end

  private
    def reset_console_records!
      Symphony::RunAttempt.delete_all
      Symphony::RetryEntry.delete_all
      Symphony::PersistedIssue.delete_all
      Symphony::OrchestratorState.delete_all
      Symphony::ManagedIssue.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end
end
