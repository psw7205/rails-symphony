require "test_helper"

class Symphony::ServiceConfigTest < ActiveSupport::TestCase
  test "applies defaults for missing values" do
    config = Symphony::ServiceConfig.new({})
    assert_equal 30_000, config.poll_interval_ms
    assert_equal 10, config.max_concurrent_agents
    assert_equal 20, config.max_turns
    assert_equal 300_000, config.max_retry_backoff_ms
    assert_equal "codex app-server", config.codex_command
    assert_equal 3_600_000, config.codex_turn_timeout_ms
    assert_equal 5_000, config.codex_read_timeout_ms
    assert_equal 300_000, config.codex_stall_timeout_ms
    assert_equal 60_000, config.hooks_timeout_ms
  end

  test "reads tracker config" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "kind" => "linear", "project_slug" => "my-project" }
    })
    assert_equal "linear", config.tracker_kind
    assert_equal "my-project", config.tracker_project_slug
  end

  test "resolves $VAR environment variables" do
    ENV["TEST_SYMPHONY_KEY"] = "secret123"
    config = Symphony::ServiceConfig.new({
      "tracker" => { "api_key" => "$TEST_SYMPHONY_KEY" }
    })
    assert_equal "secret123", config.tracker_api_key
  ensure
    ENV.delete("TEST_SYMPHONY_KEY")
  end

  test "expands ~ in workspace root" do
    config = Symphony::ServiceConfig.new({
      "workspace" => { "root" => "~/symphony-workspaces" }
    })
    assert_equal File.expand_path("~/symphony-workspaces"), config.workspace_root
  end

  test "preserves bare relative workspace root" do
    config = Symphony::ServiceConfig.new({
      "workspace" => { "root" => "relative_workspaces" }
    })
    assert_equal "relative_workspaces", config.workspace_root
  end

  test "returns default active and terminal states" do
    config = Symphony::ServiceConfig.new({})
    assert_equal [ "Todo", "In Progress" ], config.active_states
    assert_equal [ "Closed", "Cancelled", "Canceled", "Duplicate", "Done" ], config.terminal_states
  end

  test "parses comma-separated state strings" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "active_states" => "Todo, In Progress, Rework" }
    })
    assert_equal [ "Todo", "In Progress", "Rework" ], config.active_states
  end

  test "reads per-state concurrency limits" do
    config = Symphony::ServiceConfig.new({
      "agent" => { "max_concurrent_agents_by_state" => { "merging" => 2 } }
    })
    assert_equal 2, config.max_concurrent_agents_for_state("Merging")
    assert_nil config.max_concurrent_agents_for_state("Todo")
  end

  test "validate! returns ok for valid config" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "kind" => "linear", "api_key" => "tok_test", "project_slug" => "proj" }
    })
    assert_equal :ok, config.validate!
  end

  test "validate! accepts database tracker config" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "kind" => "database" }
    })

    assert_equal :ok, config.validate!
  end

  test "validate! accepts github tracker config" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "kind" => "github" }
    })

    assert_equal :ok, config.validate!
  end

  test "validate! returns error for missing tracker kind" do
    config = Symphony::ServiceConfig.new({})
    result = config.validate!
    assert_equal :validation_error, result[:error]
  end

  test "treats empty $VAR resolution as missing" do
    ENV["EMPTY_KEY"] = ""
    config = Symphony::ServiceConfig.new({
      "tracker" => { "api_key" => "$EMPTY_KEY" }
    })
    assert_nil config.tracker_api_key
  ensure
    ENV.delete("EMPTY_KEY")
  end
end
