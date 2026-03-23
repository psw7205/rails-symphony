require "test_helper"
require "webmock/minitest"

class Symphony::Trackers::GithubIssuesIntegrationTest < ActiveSupport::TestCase
  setup do
    @endpoint = "https://api.github.com"
  end

  test "full workflow config parse to github tracker fetch" do
    config = Symphony::ServiceConfig.new(
      "tracker" => {
        "kind" => "github",
        "repo" => "owner/repo",
        "api_key" => "ghp_test"
      }
    )
    tracker = Symphony::Trackers::GithubIssues.new(
      api_key: config.tracker_api_key,
      repo: config.tracker_repo,
      endpoint: config.tracker_endpoint,
      active_states: [ "Todo", "In Progress" ]
    )

    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { labels: "Todo", state: "open", per_page: "100", page: "1" })
      .to_return(
        status: 200,
        body: fixture_body("issues_page1.json"),
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { labels: "In Progress", state: "open", per_page: "100", page: "1" })
      .to_return(
        status: 200,
        body: "[]",
        headers: { "Content-Type" => "application/json" }
      )

    result = tracker.fetch_candidate_issues(active_states: [ "Todo", "In Progress" ])

    assert result[:ok]
    assert_equal [ "owner/repo#101", "owner/repo#102" ], result[:issues].map(&:identifier).sort
  end

  test "pagination across multiple pages" do
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { labels: "Todo", state: "open", per_page: "100", page: "1" })
      .to_return(
        status: 200,
        body: fixture_body("issues_page1.json"),
        headers: {
          "Content-Type" => "application/json",
          "Link" => '<https://api.github.com/repos/owner/repo/issues?labels=Todo&state=open&per_page=100&page=2>; rel="next"'
        }
      )
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { labels: "Todo", state: "open", per_page: "100", page: "2" })
      .to_return(
        status: 200,
        body: fixture_body("issues_page2.json"),
        headers: { "Content-Type" => "application/json" }
      )

    tracker = Symphony::Trackers::GithubIssues.new(
      api_key: "ghp_test",
      repo: "owner/repo",
      endpoint: @endpoint,
      active_states: [ "Todo" ]
    )

    result = tracker.fetch_candidate_issues(active_states: [ "Todo" ])

    assert result[:ok]
    assert_equal [ "owner/repo#101", "owner/repo#102", "owner/repo#103" ], result[:issues].map(&:identifier).sort
  end

  test "issue with no matching label defaults to first active state" do
    tracker = Symphony::Trackers::GithubIssues.new(
      api_key: "ghp_test",
      repo: "owner/repo",
      endpoint: @endpoint,
      active_states: [ "Todo", "In Progress" ]
    )
    stub_request(:get, "#{@endpoint}/repos/owner/repo/issues")
      .with(query: { state: "all", per_page: "100", page: "1" })
      .to_return(
        status: 200,
        body: fixture_body("issue_single.json"),
        headers: { "Content-Type" => "application/json" }
      )

    result = tracker.fetch_issue_states_by_ids([ "node-201" ])

    assert result[:ok]
    assert_equal "Todo", result[:issues].first.state
  end

  private
    def fixture_body(name)
      file_fixture("github/#{name}").read
    end
end
