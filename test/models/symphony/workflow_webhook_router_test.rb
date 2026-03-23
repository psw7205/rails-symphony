require "test_helper"

class Symphony::WorkflowWebhookRouterTest < ActiveSupport::TestCase
  setup do
    reset_console_records!
  end

  teardown do
    reset_console_records!
  end

  test "routes GitHub webhook payloads by repository" do
    workflow = build_github_workflow(
      slug: "router-github-workflow",
      name: "Router GitHub Workflow",
      repo: "octocat/Hello-World"
    )

    result = Symphony::WorkflowWebhookRouter.route(
      provider: "github",
      event_type: "issues",
      payload: github_payload
    )

    assert_equal false, result[:ignored]
    assert_equal [ workflow.id ], result[:workflows].map(&:id)
  end

  test "routes Linear webhook payloads by project slug" do
    workflow = build_linear_workflow(
      slug: "router-linear-workflow",
      name: "Router Linear Workflow",
      project_slug: "ops-project"
    )

    result = Symphony::WorkflowWebhookRouter.route(
      provider: "linear",
      event_type: "Issue",
      payload: linear_payload
    )

    assert_equal false, result[:ignored]
    assert_equal [ workflow.id ], result[:workflows].map(&:id)
  end

  test "excludes inactive workflows from routing" do
    build_github_workflow(
      slug: "router-inactive-workflow",
      name: "Router Inactive Workflow",
      repo: "octocat/Hello-World",
      status: "inactive"
    )

    result = Symphony::WorkflowWebhookRouter.route(
      provider: "github",
      event_type: "issues",
      payload: github_payload
    )

    assert_empty result[:workflows]
  end

  test "fans out to multiple workflows that share the same tracker config" do
    first = build_linear_workflow(
      slug: "router-fanout-one",
      name: "Router Fanout One",
      project_slug: "ops-project"
    )
    second = build_linear_workflow(
      slug: "router-fanout-two",
      name: "Router Fanout Two",
      project_slug: "ops-project"
    )

    result = Symphony::WorkflowWebhookRouter.route(
      provider: "linear",
      event_type: "Issue",
      payload: linear_payload
    )

    assert_equal [ first.id, second.id ].sort, result[:workflows].map(&:id).sort
  end

  private
    def github_payload
      JSON.parse(Rails.root.join("test/fixtures/files/webhooks/github/issues_opened.json").read)
    end

    def linear_payload
      JSON.parse(Rails.root.join("test/fixtures/files/webhooks/linear/issue_created.json").read)
    end

    def reset_console_records!
      Symphony::OrchestratorState.delete_all
      Symphony::WorkflowTriggerEvent.delete_all
      Symphony::ManagedIssue.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end

    def build_github_workflow(slug:, name:, repo:, status: "active")
      build_workflow(
        slug: slug,
        name: name,
        status: status,
        tracker_kind: "github",
        tracker_config: { "tracker" => { "repo" => repo, "webhook_secret" => "github-secret", "api_key" => "$GITHUB_TOKEN" } }
      )
    end

    def build_linear_workflow(slug:, name:, project_slug:, status: "active")
      build_workflow(
        slug: slug,
        name: name,
        status: status,
        tracker_kind: "linear",
        tracker_config: { "tracker" => { "project_slug" => project_slug, "webhook_secret" => "linear-secret", "api_key" => "$LINEAR_API_KEY" } }
      )
    end

    def build_workflow(slug:, name:, status:, tracker_kind:, tracker_config:)
      project = Symphony::ManagedProject.create!(name: "#{name} Project", slug: "#{slug}-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(name: "#{name} Tracker", kind: tracker_kind, status: "active", config: tracker_config)
      agent_connection = Symphony::AgentConnection.create!(name: "#{name} Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: name,
        slug: slug,
        status: status
      )
    end
end
