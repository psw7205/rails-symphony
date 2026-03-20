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
