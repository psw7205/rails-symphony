require "test_helper"
require "webmock/minitest"

class Symphony::Trackers::LinearTest < ActiveSupport::TestCase
  setup do
    @endpoint = "https://api.linear.app/graphql"
    @tracker = Symphony::Trackers::Linear.new(
      api_key: "lin_api_test",
      endpoint: @endpoint,
      project_slug: "my-project"
    )
  end

  test "fetch_candidate_issues returns normalized issues" do
    stub_linear_poll([ make_linear_node("id1", "MT-1", "Fix bug", "Todo", priority: 1) ])

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert result[:ok]
    assert_equal 1, result[:issues].length

    issue = result[:issues].first
    assert_equal "id1", issue.id
    assert_equal "MT-1", issue.identifier
    assert_equal "Todo", issue.state
    assert_equal 1, issue.priority
  end

  test "fetch_candidate_issues paginates" do
    page1_body = {
      data: {
        issues: {
          nodes: [ make_linear_node("id1", "MT-1", "First", "Todo") ],
          pageInfo: { hasNextPage: true, endCursor: "cursor1" }
        }
      }
    }
    page2_body = {
      data: {
        issues: {
          nodes: [ make_linear_node("id2", "MT-2", "Second", "Todo") ],
          pageInfo: { hasNextPage: false, endCursor: nil }
        }
      }
    }

    stub_request(:post, @endpoint)
      .to_return(
        { status: 200, body: page1_body.to_json, headers: { "Content-Type" => "application/json" } },
        { status: 200, body: page2_body.to_json, headers: { "Content-Type" => "application/json" } }
      )

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert result[:ok]
    assert_equal 2, result[:issues].length
    assert_equal %w[MT-1 MT-2], result[:issues].map(&:identifier)
  end

  test "returns error when hasNextPage is true without endCursor" do
    body = {
      data: {
        issues: {
          nodes: [ make_linear_node("id1", "MT-1", "First", "Todo") ],
          pageInfo: { hasNextPage: true, endCursor: nil }
        }
      }
    }

    stub_request(:post, @endpoint)
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert_equal :linear_missing_end_cursor, result[:error]
  end

  test "fetch_issue_states_by_ids returns matching issues" do
    body = {
      data: {
        issues: {
          nodes: [
            make_linear_node("id1", "MT-1", "Bug", "Done"),
            make_linear_node("id2", "MT-2", "Feature", "In Progress")
          ]
        }
      }
    }

    stub_request(:post, @endpoint)
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @tracker.fetch_issue_states_by_ids([ "id1", "id2" ])
    assert result[:ok]
    assert_equal 2, result[:issues].length
  end

  test "fetch_issue_states_by_ids with empty ids" do
    result = @tracker.fetch_issue_states_by_ids([])
    assert result[:ok]
    assert_empty result[:issues]
  end

  test "normalizes labels to lowercase" do
    node = make_linear_node("id1", "MT-1", "Bug", "Todo")
    node[:labels] = { nodes: [ { name: "Bug" }, { name: "URGENT" } ] }

    stub_linear_poll([ node ])

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert_equal [ "bug", "urgent" ], result[:issues].first.labels
  end

  test "extracts blockers from inverseRelations" do
    node = make_linear_node("id1", "MT-1", "Bug", "Todo")
    node[:inverseRelations] = {
      nodes: [
        { type: "blocks", issue: { id: "b1", identifier: "MT-0", state: { name: "In Progress" } } },
        { type: "related", issue: { id: "r1", identifier: "MT-9", state: { name: "Todo" } } }
      ]
    }

    stub_linear_poll([ node ])

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    blockers = result[:issues].first.blocked_by
    assert_equal 1, blockers.length
    assert_equal "b1", blockers.first["id"]
    assert_equal "MT-0", blockers.first["identifier"]
  end

  test "handles API error status" do
    stub_request(:post, @endpoint)
      .to_return(status: 401, body: "Unauthorized")

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert_equal :linear_api_status, result[:error]
  end

  test "handles GraphQL errors" do
    body = { errors: [ { message: "Something went wrong" } ] }
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert_equal :linear_graphql_errors, result[:error]
  end

  test "handles transport error" do
    stub_request(:post, @endpoint).to_timeout

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])
    assert_equal :linear_transport_error, result[:error]
  end

  private

    def make_linear_node(id, identifier, title, state, priority: nil)
      {
        id: id,
        identifier: identifier,
        title: title,
        description: nil,
        priority: priority,
        state: { name: state },
        branchName: nil,
        url: "https://linear.app/issue/#{identifier}",
        labels: { nodes: [] },
        inverseRelations: { nodes: [] },
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:00:00Z"
      }
    end

    def stub_linear_poll(nodes)
      body = {
        data: {
          issues: {
            nodes: nodes,
            pageInfo: { hasNextPage: false, endCursor: nil }
          }
        }
      }
      stub_request(:post, @endpoint)
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end
end
