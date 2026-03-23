require "test_helper"

class Symphony::Trackers::BaseTest < ActiveSupport::TestCase
  test "capabilities returns the base read-only set" do
    capabilities = Symphony::Trackers::Base.new.capabilities

    assert_equal [ :read_issues, :read_issue_states, :refresh ], capabilities
  end
end
