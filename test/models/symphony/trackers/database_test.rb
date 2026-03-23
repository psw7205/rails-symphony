require "test_helper"

class Symphony::Trackers::DatabaseTest < ActiveSupport::TestCase
  setup do
    @workflow = build_database_workflow
    @tracker = Symphony::Trackers::Database.new(managed_workflow: @workflow)

    Symphony::ManagedIssue.create!(
      managed_workflow: @workflow,
      identifier: "DB-1",
      title: "Todo issue",
      state: "Todo",
      priority: "2"
    )
    Symphony::ManagedIssue.create!(
      managed_workflow: @workflow,
      identifier: "DB-2",
      title: "In progress issue",
      state: "In Progress",
      priority: "1"
    )
    Symphony::ManagedIssue.create!(
      managed_workflow: @workflow,
      identifier: "DB-3",
      title: "Done issue",
      state: "Done",
      priority: "3"
    )
  end

  test "capabilities include full database tracker access" do
    assert_equal(
      [ :read_issues, :read_issue_states, :refresh, :create_issue, :update_issue, :transition_issue ],
      @tracker.capabilities
    )
  end

  test "fetch_candidate_issues returns active state managed issues" do
    result = @tracker.fetch_candidate_issues(active_states: [ "Todo", "In Progress" ])

    assert result[:ok]
    assert_equal [ "DB-1", "DB-2" ], result[:issues].map(&:identifier).sort
    assert result[:issues].all? { |issue| issue.is_a?(Symphony::Issue) }
  end

  test "fetch_issue_states_by_ids returns matching managed issues" do
    issue_ids = Symphony::ManagedIssue.where(identifier: [ "DB-1", "DB-3" ]).pluck(:id).map(&:to_s)

    result = @tracker.fetch_issue_states_by_ids(issue_ids)

    assert result[:ok]
    assert_equal [ "DB-1", "DB-3" ], result[:issues].map(&:identifier).sort
  end

  test "fetch_issues_by_states filters case-insensitively" do
    result = @tracker.fetch_issues_by_states([ "done" ])

    assert result[:ok]
    assert_equal [ "DB-3" ], result[:issues].map(&:identifier)
  end

  test "fetch_issues_by_states with empty list returns empty" do
    result = @tracker.fetch_issues_by_states([])

    assert result[:ok]
    assert_empty result[:issues]
  end

  private
    def build_database_workflow
      project = Symphony::ManagedProject.create!(name: "Database Tracker Project", slug: "database-tracker-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "Database Tracker", kind: "database", status: "active", config: {})
      agent_connection = Symphony::AgentConnection.create!(name: "Database Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Database Tracker Workflow",
        slug: "database-tracker-workflow",
        status: "active"
      )
    end
end
