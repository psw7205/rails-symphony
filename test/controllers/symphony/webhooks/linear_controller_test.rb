require "test_helper"
require "openssl"

class LinearWebhookControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    reset_console_records!
  end

  teardown do
    clear_enqueued_jobs
    reset_console_records!
  end

  test "POST /webhooks/linear accepts valid signatures and enqueues matching workflows" do
    workflow = build_linear_workflow
    payload = linear_payload

    assert_enqueued_with(job: Symphony::WorkflowPollJob) do
      post "/webhooks/linear", params: payload, headers: linear_headers(payload, signature: linear_signature(payload))
    end

    assert_response 202
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, event.managed_workflow_id
    assert_equal "linear", event.provider
    assert_equal "webhook_linear", event.source
    assert_equal "enqueued", event.status
  end

  test "POST /webhooks/linear rejects invalid signatures" do
    workflow = build_linear_workflow
    payload = linear_payload

    post "/webhooks/linear", params: payload, headers: linear_headers(payload, signature: "deadbeef")

    assert_response 401
    assert_equal 0, enqueued_jobs.size
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, event.managed_workflow_id
    assert_equal "rejected_signature", event.status
    assert_equal "invalid", event.signature_state
  end

  test "POST /webhooks/linear rejects missing signatures" do
    workflow = build_linear_workflow
    payload = linear_payload

    post "/webhooks/linear", params: payload, headers: linear_headers(payload, signature: nil)

    assert_response 401
    assert_equal 0, enqueued_jobs.size
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, event.managed_workflow_id
    assert_equal "rejected_signature", event.status
    assert_equal "missing", event.signature_state
  end

  test "POST /webhooks/linear records duplicate deliveries without enqueueing another job" do
    build_linear_workflow
    payload = linear_payload
    headers = linear_headers(payload, signature: linear_signature(payload))

    post "/webhooks/linear", params: payload, headers: headers
    clear_enqueued_jobs

    post "/webhooks/linear", params: payload, headers: headers

    assert_response 202
    assert_equal 0, enqueued_jobs.size
    event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal "ignored_duplicate", event.status
  end

  private
    def linear_payload
      JSON.parse(Rails.root.join("test/fixtures/files/webhooks/linear/issue_created.json").read)
        .merge("webhookTimestamp" => (Time.current.to_f * 1000).to_i)
        .to_json
    end

    def linear_signature(payload)
      OpenSSL::HMAC.hexdigest("SHA256", "linear-secret", payload)
    end

    def linear_headers(payload, signature:)
      headers = {
        "CONTENT_TYPE" => "application/json",
        "HTTP_LINEAR_EVENT" => "Issue",
        "HTTP_LINEAR_DELIVERY" => "234d1a4e-b617-4388-90fe-adc3633d6b72",
        "RAW_POST_DATA" => payload
      }
      headers["HTTP_LINEAR_SIGNATURE"] = signature if signature
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

    def build_linear_workflow
      project = Symphony::ManagedProject.create!(name: "Linear Webhook Project", slug: "linear-webhook-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Linear Webhook Tracker",
        kind: "linear",
        status: "active",
        config: { "tracker" => { "project_slug" => "ops-project", "webhook_secret" => "linear-secret", "api_key" => "$LINEAR_API_KEY" } }
      )
      agent_connection = Symphony::AgentConnection.create!(name: "Linear Webhook Agent", kind: "codex", status: "active", config: {})

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Linear Webhook Workflow",
        slug: "linear-webhook-workflow",
        status: "active"
      )
    end
end
