require "test_helper"
require "openssl"

class GithubWebhookControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    reset_console_records!
  end

  teardown do
    clear_enqueued_jobs
    reset_console_records!
  end

  test "POST /webhooks/github accepts valid signatures and enqueues matching workflows" do
    workflow = build_github_workflow
    payload = github_payload

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      post "/webhooks/github", params: payload, headers: github_headers(payload, signature: github_signature(payload))
    end

    assert_response 202
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, event.managed_workflow_id
    assert_equal "github", event.provider
    assert_equal "webhook_github", event.source
    assert_equal "enqueued", event.status
  end

  test "POST /webhooks/github rejects invalid signatures" do
    workflow = build_github_workflow
    payload = github_payload

    post "/webhooks/github", params: payload, headers: github_headers(payload, signature: "sha256=deadbeef")

    assert_response 401
    assert_equal 0, enqueued_jobs.size
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, event.managed_workflow_id
    assert_equal "rejected_signature", event.status
    assert_equal "invalid", event.signature_state
  end

  test "POST /webhooks/github rejects missing signatures" do
    workflow = build_github_workflow
    payload = github_payload

    post "/webhooks/github", params: payload, headers: github_headers(payload, signature: nil)

    assert_response 401
    assert_equal 0, enqueued_jobs.size
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, event.managed_workflow_id
    assert_equal "rejected_signature", event.status
    assert_equal "missing", event.signature_state
  end

  test "POST /webhooks/github records duplicate deliveries without enqueueing another job" do
    build_github_workflow
    payload = github_payload
    headers = github_headers(payload, signature: github_signature(payload))

    post "/webhooks/github", params: payload, headers: headers
    clear_enqueued_jobs

    post "/webhooks/github", params: payload, headers: headers

    assert_response 202
    assert_equal 0, enqueued_jobs.size
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal "ignored_duplicate", event.status
  end

  private
    def github_payload
      Rails.root.join("test/fixtures/files/webhooks/github/issues_opened.json").read
    end

    def github_signature(payload)
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "github-secret", payload)}"
    end

    def github_headers(payload, signature:)
      headers = {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_GITHUB_EVENT" => "issues",
        "HTTP_X_GITHUB_DELIVERY" => "72d3162e-cc78-11e3-81ab-4c9367dc0958",
        "RAW_POST_DATA" => payload
      }
      headers["HTTP_X_HUB_SIGNATURE_256"] = signature if signature
      headers
    end

    def reset_console_records!
      Symphony::OrchestratorState.delete_all
      Symphony::WorkflowTriggerEvent.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end

    def build_github_workflow
      project = Symphony::ManagedProject.create!(name: "GitHub Webhook Project", slug: "github-webhook-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "GitHub Webhook Tracker",
        kind: "github",
        status: "active",
        config: { "tracker" => { "repo" => "octocat/Hello-World", "webhook_secret" => "github-secret", "api_key" => "$GITHUB_TOKEN" } }
      )
      agent_connection = Symphony::AgentConnection.create!(name: "GitHub Webhook Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "GitHub Webhook Workflow",
        slug: "github-webhook-workflow",
        status: "active"
      )
    end
end
