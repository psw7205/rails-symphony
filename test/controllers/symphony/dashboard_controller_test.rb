require "test_helper"

class Symphony::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "GET / renders dashboard without orchestrator" do
    Symphony.orchestrator = nil
    get root_path
    assert_response :success
    assert_includes response.body, "Operations Dashboard"
    assert_includes response.body, "No active sessions"
  end
end
