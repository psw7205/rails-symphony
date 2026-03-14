require "test_helper"

class Symphony::IssueTest < ActiveSupport::TestCase
  test "initializes with all required fields" do
    issue = Symphony::Issue.new(
      id: "abc123", identifier: "MT-42", title: "Fix bug",
      description: "Details", priority: 1, state: "Todo",
      labels: [ "urgent" ], blocked_by: [], url: "https://linear.app/..."
    )
    assert_equal "abc123", issue.id
    assert_equal "MT-42", issue.identifier
    assert_equal 1, issue.priority
    assert_equal [ "urgent" ], issue.labels
  end

  test "labels default to empty array" do
    issue = Symphony::Issue.new(id: "x", identifier: "X-1", title: "t", state: "Todo")
    assert_equal [], issue.labels
    assert_equal [], issue.blocked_by
  end

  test "has_non_terminal_blockers? returns true when blocker state is active" do
    issue = Symphony::Issue.new(
      id: "x", identifier: "X-1", title: "t", state: "Todo",
      blocked_by: [ { "id" => "b1", "identifier" => "X-2", "state" => "In Progress" } ]
    )
    assert issue.has_non_terminal_blockers?([ "done", "closed", "cancelled", "canceled", "duplicate" ])
  end

  test "has_non_terminal_blockers? returns false when all blockers terminal" do
    issue = Symphony::Issue.new(
      id: "x", identifier: "X-1", title: "t", state: "Todo",
      blocked_by: [ { "id" => "b1", "identifier" => "X-2", "state" => "Done" } ]
    )
    refute issue.has_non_terminal_blockers?([ "done", "closed", "cancelled", "canceled", "duplicate" ])
  end
end
