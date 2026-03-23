require "test_helper"
require "openssl"
require "webmock/minitest"

class Symphony::WorkflowTriggeringIntegrationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
    stub_github_issue_fetches
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Symphony::WorkflowRuntimeManager.clear!
    reset_console_records!
  end

  test "valid webhook triggers a workflow tick and updates dashboard and workflow detail trigger health" do
    workflow = build_github_workflow(status: "active")

    post "/webhooks/github", params: github_payload, headers: github_headers(github_payload, signature: github_signature(github_payload))

    assert_response 202
    workflow_job = enqueued_jobs.find { |job| job[:job] == Symphony::WorkflowPollJob }
    workflow_job_args = workflow_job[:args].first.symbolize_keys.except(:_aj_ruby2_keywords)
    Symphony::WorkflowPollJob.perform_now(**workflow_job_args)
    trigger_event = Symphony::WorkflowTriggerEvent.order(:id).last
    assert_equal workflow.id, trigger_event.managed_workflow_id
    assert_equal "succeeded", trigger_event.status

    get root_path
    assert_response :success
    assert_includes response.body, "webhook_github"
    assert_includes response.body, "succeeded"

    get "/workflows/#{workflow.id}"
    assert_response :success
    assert_includes response.body, "Recent trigger events"
    assert_includes response.body, "webhook_github"
    assert_includes response.body, "succeeded"
  end

  test "invalid signature does not enqueue work and shows a rejected trigger event on workflow detail" do
    workflow = build_github_workflow(status: "active")

    post "/webhooks/github", params: github_payload, headers: github_headers(github_payload, signature: "sha256=deadbeef")

    assert_response 401
    assert_equal 0, enqueued_jobs.size

    get "/workflows/#{workflow.id}"
    assert_response :success
    assert_includes response.body, "rejected_signature"
    assert_includes response.body, "signature_mismatch"
  end

  test "paused workflows ignore recurring poll and webhook-triggered execution" do
    workflow = build_github_workflow(status: "inactive")

    assert_no_difference("Symphony::WorkflowTriggerEvent.count") do
      post "/webhooks/github", params: github_payload, headers: github_headers(github_payload, signature: github_signature(github_payload))
    end

    assert_response 202
    Symphony::PollJob.perform_now

    assert_equal "inactive", workflow.reload.status
    assert_equal 0, enqueued_jobs.count { |job| job[:job] == Symphony::WorkflowPollJob }
    assert_equal 0, Symphony::WorkflowTriggerEvent.count
  end

  private
    def github_payload
      Rails.root.join("test/fixtures/files/webhooks/github/issues_opened.json").read
    end

    def github_signature(payload)
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "github-secret", payload)}"
    end

    def github_headers(payload, signature:)
      {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_GITHUB_EVENT" => "issues",
        "HTTP_X_GITHUB_DELIVERY" => "72d3162e-cc78-11e3-81ab-4c9367dc0958",
        "HTTP_X_HUB_SIGNATURE_256" => signature,
        "RAW_POST_DATA" => payload
      }
    end

    def stub_github_issue_fetches
      stub_request(:get, "https://api.github.com/repos/octocat/Hello-World/issues")
        .with(query: hash_including({ "labels" => "Todo", "state" => "open", "per_page" => "100", "page" => "1" }))
        .to_return(
          status: 200,
          body: Rails.root.join("test/fixtures/files/github/issues_page1.json").read,
          headers: { "Content-Type" => "application/json" }
        )
      stub_request(:get, "https://api.github.com/repos/octocat/Hello-World/issues")
        .with(query: hash_including({ "labels" => "In Progress", "state" => "open", "per_page" => "100", "page" => "1" }))
        .to_return(
          status: 200,
          body: "[]",
          headers: { "Content-Type" => "application/json" }
        )
    end

    def reset_console_records!
      Symphony::RunAttempt.delete_all
      Symphony::RetryEntry.delete_all
      Symphony::PersistedIssue.delete_all
      Symphony::OrchestratorState.delete_all
      Symphony::WorkflowTriggerEvent.delete_all
      Symphony::ManagedIssue.delete_all
      Symphony::ManagedWorkflow.delete_all
      Symphony::AgentConnection.delete_all
      Symphony::TrackerConnection.delete_all
      Symphony::ManagedProject.delete_all
    end

    def build_github_workflow(status:)
      project = Symphony::ManagedProject.create!(name: "Integration Trigger Project", slug: "integration-trigger-project", status: "active")
      tracker_connection = Symphony::TrackerConnection.create!(
        name: "Integration Trigger Tracker",
        kind: "github",
        status: "active",
        config: {
          "tracker" => {
            "repo" => "octocat/Hello-World",
            "api_key" => "ghp_test",
            "webhook_secret" => "github-secret"
          }
        }
      )
      agent_connection = Symphony::AgentConnection.create!(
        name: "Integration Trigger Agent",
        kind: "codex",
        status: "active",
        config: { "codex" => { "command" => "bin/codex app-server" } }
      )

      Symphony::ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: "Integration Trigger Workflow",
        slug: "integration-trigger-workflow-#{status}",
        status: status,
        prompt_template: "Integration trigger prompt",
        runtime_config: { "workspace" => { "root" => "integration-trigger-workspaces" } }
      )
    end
end
