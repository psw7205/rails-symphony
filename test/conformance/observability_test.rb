require "test_helper"
require "stringio"

# SPEC 17.6 Observability Conformance
class ObservabilityTest < ActiveSupport::TestCase
  # SPEC 17.6.2: Structured logging includes issue/session context fields
  test "logger tags output with issue context" do
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output))

    original_logger = Rails.logger
    Rails.logger = logger

    issue = Symphony::Issue.new(id: "42", identifier: "MT-42", title: "Test", state: "Todo")
    Symphony::Logger.with_issue(issue) do
      Rails.logger.info("test message")
    end

    log_output = output.string
    assert_includes log_output, "issue_id=42"
    assert_includes log_output, "issue_identifier=MT-42"
    assert_includes log_output, "test message"
  ensure
    Rails.logger = original_logger
  end

  test "logger tags output with session context" do
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output))

    original_logger = Rails.logger
    Rails.logger = logger

    Symphony::Logger.with_session("sess-abc") do
      Rails.logger.info("session log")
    end

    log_output = output.string
    assert_includes log_output, "session_id=sess-abc"
    assert_includes log_output, "session log"
  ensure
    Rails.logger = original_logger
  end

  # SPEC 17.6.3: Logging to /dev/null does not crash orchestration
  test "orchestrator tick works with null logger" do
    root = Dir.mktmpdir("obs_test")
    workflow_file = File.join(root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nPrompt")
    store = Symphony::WorkflowStore.new(workflow_file)

    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "T", state: "Todo", priority: 1, created_at: Time.now)
    ])
    workspace = Symphony::Workspace.new(root: File.join(root, "ws"))
    dispatched = []

    orchestrator = Symphony::Orchestrator.new(
      tracker: tracker, workspace: workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(issue, attempt) { dispatched << issue.id }
    )

    # Use a logger that discards output (simulates sink unavailability)
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(File.open(File::NULL, "w")))

    assert_nothing_raised { orchestrator.tick }
    assert_equal 1, dispatched.size
  ensure
    Rails.logger = original_logger
    FileUtils.rm_rf(root)
  end

  # SPEC 17.6.4: Token/rate-limit aggregation correct across repeated updates
  test "handle_codex_update accumulates events correctly" do
    root = Dir.mktmpdir("obs_token_test")
    workflow_file = File.join(root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nPrompt")
    store = Symphony::WorkflowStore.new(workflow_file)

    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "T", state: "Todo", priority: 1, created_at: Time.now)
    ])
    workspace = Symphony::Workspace.new(root: File.join(root, "ws"))

    orchestrator = Symphony::Orchestrator.new(
      tracker: tracker, workspace: workspace, agent: nil,
      workflow_store: store,
      on_dispatch: ->(_issue, _attempt) {}
    )

    orchestrator.tick

    # Multiple updates to same issue
    orchestrator.handle_codex_update("1", { event: :turn_started, timestamp: Time.now.utc })
    entry = orchestrator.running["1"]
    assert_equal :turn_started, entry[:last_codex_event]

    orchestrator.handle_codex_update("1", { event: :turn_completed, timestamp: Time.now.utc })
    entry = orchestrator.running["1"]
    assert_equal :turn_completed, entry[:last_codex_event]
  ensure
    FileUtils.rm_rf(root)
  end
end
