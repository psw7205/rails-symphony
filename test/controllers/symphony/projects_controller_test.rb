require "test_helper"

class Symphony::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_console_records!
  end

  teardown do
    reset_console_records!
  end

  test "GET /projects renders managed projects" do
    Symphony::ManagedProject.create!(name: "Project Alpha", slug: "project-alpha", status: "active")
    Symphony::ManagedProject.create!(name: "Project Beta", slug: "project-beta", status: "inactive")

    get "/projects"
    assert_response :success
    assert_includes response.body, "Project Alpha"
    assert_includes response.body, "Project Beta"
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
