require "test_helper"

class Symphony::AgentConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
  end

  teardown do
    reset_console_records!
  end

  test "GET /agent_connections/new renders the agent connection form" do
    get "/agent_connections/new"
    assert_response :success
    assert_includes response.body, "New agent connection"
  end

  test "POST /agent_connections creates an agent connection" do
    post "/agent_connections", params: {
      agent_connection: {
        name: "Codex Connection",
        kind: "codex",
        status: "active",
        config_json: "{\"codex\":{\"command\":\"bin/codex app-server\"}}"
      }
    }

    connection = Symphony::AgentConnection.order(:id).last
    assert_redirected_to "/projects"
    assert_equal "Codex Connection", connection.name
    assert_equal "bin/codex app-server", connection.config["codex"]["command"]
  end

  test "POST /agent_connections renders validation errors" do
    post "/agent_connections", params: {
      agent_connection: {
        name: "",
        kind: "",
        status: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Name can&#39;t be blank"
  end

  test "GET /agent_connections/:id/edit renders the agent connection form" do
    agent_connection = Symphony::AgentConnection.create!(
      name: "Editable Codex Connection",
      kind: "codex",
      status: "active",
      config: { "codex" => { "command" => "bin/codex app-server" } }
    )

    get "/agent_connections/#{agent_connection.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit agent connection"
    assert_includes response.body, "Editable Codex Connection"
  end

  test "PATCH /agent_connections/:id updates an agent connection" do
    agent_connection = Symphony::AgentConnection.create!(
      name: "Editable Codex Connection",
      kind: "codex",
      status: "active",
      config: { "codex" => { "command" => "bin/codex app-server" } }
    )

    patch "/agent_connections/#{agent_connection.id}", params: {
      agent_connection: {
        name: "Updated Codex Connection",
        kind: "codex",
        status: "inactive",
        config_json: "{\"codex\":{\"command\":\"bin/codex worker\"}}"
      }
    }

    assert_redirected_to "/projects"
    agent_connection.reload
    assert_equal "Updated Codex Connection", agent_connection.name
    assert_equal "codex", agent_connection.kind
    assert_equal "inactive", agent_connection.status
    assert_equal "bin/codex worker", agent_connection.config["codex"]["command"]
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
