require "test_helper"
require "webmock/minitest"

class Symphony::Trackers::GithubIssuesTest < ActiveSupport::TestCase
  setup do
    @endpoint = "https://api.github.com"
    @tracker = Symphony::Trackers::GithubIssues.new(
      api_key: "ghp_test",
      repo: "owner/repo",
      endpoint: @endpoint,
      active_states: [ "Todo", "In Progress" ]
    )
  end

  test "capabilities stay read-only" do
    assert_equal [ :read_issues, :read_issue_states, :refresh ], @tracker.capabilities
  end

  test "initializes a connection and sends auth headers" do
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(
        headers: {
          "Authorization" => "token ghp_test",
          "Accept" => "application/vnd.github+json"
        },
        query: { labels: "Todo", state: "open", per_page: "100", page: "1" }
      )
      .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])

    assert result[:ok]
  end

  test "fetch_candidate_issues returns issues matching active state labels" do
    stub_github_issues(
      query: { labels: "Todo", state: "open", per_page: "100", page: "1" },
      body: [ make_issue(node_id: "node-1", number: 1, title: "Todo issue", labels: [ "Todo", "priority:2" ]) ]
    )
    stub_github_issues(
      query: { labels: "In Progress", state: "open", per_page: "100", page: "1" },
      body: [ make_issue(node_id: "node-2", number: 2, title: "In progress issue", labels: [ "In Progress" ]) ]
    )

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo", "In Progress" ])

    assert result[:ok]
    assert_equal [ "owner/repo#1", "owner/repo#2" ], result[:issues].map(&:identifier).sort
    assert_equal [ "In Progress", "Todo" ], result[:issues].map(&:state).sort
    assert_equal 2, result[:issues].find { |issue| issue.identifier == "owner/repo#1" }.priority
  end

  test "fetch_candidate_issues paginates across GitHub link headers" do
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { labels: "Todo", state: "open", per_page: "100", page: "1" })
      .to_return(
        status: 200,
        body: [ make_issue(node_id: "node-1", number: 1, title: "Todo issue one", labels: [ "Todo" ]) ].to_json,
        headers: {
          "Content-Type" => "application/json",
          "Link" => '<https://api.github.com/repos/owner/repo/issues?labels=Todo&state=open&per_page=100&page=2>; rel="next"'
        }
      )
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { labels: "Todo", state: "open", per_page: "100", page: "2" })
      .to_return(
        status: 200,
        body: [ make_issue(node_id: "node-2", number: 2, title: "Todo issue two", labels: [ "Todo" ]) ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])

    assert result[:ok]
    assert_equal [ "owner/repo#1", "owner/repo#2" ], result[:issues].map(&:identifier).sort
  end

  test "fetch_issue_states_by_ids returns issues by node_id" do
    stub_github_issues(
      query: { state: "all", per_page: "100", page: "1" },
      body: [
        make_issue(node_id: "node-1", number: 1, title: "Todo issue", labels: [ "Todo" ]),
        make_issue(node_id: "node-2", number: 2, title: "Closed issue", state: "closed", labels: [])
      ]
    )

    result = @tracker.fetch_issue_states_by_ids([ "node-1", "node-2" ])

    assert result[:ok]
    assert_equal [ "node-1", "node-2" ], result[:issues].map(&:id).sort
    assert_equal [ "Closed", "Todo" ], result[:issues].map(&:state).sort
  end

  test "fetch_issues_by_states returns issues matching given states" do
    stub_github_issues(
      query: { labels: "Todo", state: "open", per_page: "100", page: "1" },
      body: [ make_issue(node_id: "node-3", number: 3, title: "Todo state issue", labels: [ "Todo" ]) ]
    )

    result = @tracker.fetch_issues_by_states([ "Todo" ])

    assert result[:ok]
    assert_equal [ "owner/repo#3" ], result[:issues].map(&:identifier)
  end

  test "fetch_issues_by_states with empty states returns empty" do
    result = @tracker.fetch_issues_by_states([])

    assert result[:ok]
    assert_empty result[:issues]
  end

  test "handles api error status" do
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: hash_including("labels" => "Todo"))
      .to_return(status: 401, body: "Unauthorized")

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])

    assert_equal :github_api_status, result[:error]
    assert_equal 401, result[:status]
  end

  test "handles transport error" do
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: hash_including("labels" => "Todo"))
      .to_timeout

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])

    assert_equal :github_transport_error, result[:error]
  end

  test "reconfigure updates repo and rebuilds connection when endpoint changes" do
    @tracker.reconfigure(
      api_key: "ghp_reconfigured",
      repo: "other/repo",
      endpoint: "https://ghe.example/api/v3",
      active_states: [ "Todo" ]
    )

    stub_request(:get, "https://ghe.example/api/v3/repos/other/repo/issues")
      .with(
        headers: {
          "Authorization" => "token ghp_reconfigured",
          "Accept" => "application/vnd.github+json"
        },
        query: { labels: "Todo", state: "open", per_page: "100", page: "1" }
      )
      .to_return(
        status: 200,
        body: [ make_issue(node_id: "node-9", number: 9, title: "Reconfigured issue", labels: [ "Todo" ]) ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @tracker.fetch_candidate_issues(active_states: [ "Todo" ])

    assert result[:ok]
    assert_equal [ "other/repo#9" ], result[:issues].map(&:identifier)
  end

  private
    def stub_github_issues(query:, body:)
      stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
        .with(query: query)
        .to_return(
          status: 200,
          body: body.to_json,
          headers: {
            "Content-Type" => "application/json"
          }
        )
    end

    def make_issue(node_id:, number:, title:, labels:, state: "open")
      {
        node_id: node_id,
        number: number,
        title: title,
        body: "#{title} body",
        state: state,
        labels: labels.map { |label| { name: label } },
        html_url: "https://github.com/owner/repo/issues/#{number}",
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-01T00:00:00Z"
      }
    end
end
