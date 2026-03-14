require "test_helper"

class Symphony::Trackers::MemoryTest < ActiveSupport::TestCase
  setup do
    @issues = [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Task 1", state: "Todo", priority: 2, created_at: Time.now),
      Symphony::Issue.new(id: "2", identifier: "MT-2", title: "Task 2", state: "In Progress", priority: 1, created_at: Time.now),
      Symphony::Issue.new(id: "3", identifier: "MT-3", title: "Task 3", state: "Done", priority: 3, created_at: Time.now)
    ]
    @tracker = Symphony::Trackers::Memory.new(issues: @issues)
  end

  test "fetch_candidate_issues returns active state issues" do
    result = @tracker.fetch_candidate_issues(active_states: [ "Todo", "In Progress" ])
    assert result[:ok]
    assert_equal 2, result[:issues].length
    identifiers = result[:issues].map(&:identifier)
    assert_includes identifiers, "MT-1"
    assert_includes identifiers, "MT-2"
  end

  test "fetch_issue_states_by_ids returns matching issues" do
    result = @tracker.fetch_issue_states_by_ids([ "1", "3" ])
    assert result[:ok]
    assert_equal 2, result[:issues].length
  end

  test "fetch_issues_by_states filters by normalized state" do
    result = @tracker.fetch_issues_by_states([ "done" ])
    assert result[:ok]
    assert_equal 1, result[:issues].length
    assert_equal "MT-3", result[:issues].first.identifier
  end

  test "fetch_issues_by_states with empty list returns empty" do
    result = @tracker.fetch_issues_by_states([])
    assert result[:ok]
    assert_empty result[:issues]
  end
end
