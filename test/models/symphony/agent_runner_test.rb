require "test_helper"
require "tmpdir"

class Symphony::AgentRunnerTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("agent_runner_test")
    @workspace = Symphony::Workspace.new(root: @root)
    @config = Symphony::ServiceConfig.new({
      "agent" => { "max_turns" => 3 },
      "tracker" => { "active_states" => "Todo, In Progress" }
    })
    @issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Fix bug", state: "Todo")
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "runs single turn successfully" do
    agent = MockAgent.new(turn_results: [{ ok: true, event: :turn_completed }])
    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Fix bug", state: "Done")
    ])

    runner = Symphony::AgentRunner.new(
      workspace: @workspace, agent: agent, config: @config,
      tracker: tracker, prompt_template: "Fix {{ issue.identifier }}"
    )
    result = runner.run(issue: @issue)

    assert result[:ok]
    assert_equal :completed, result[:outcome]
    assert_equal 1, agent.turn_count
  end

  test "continues turns when issue stays active" do
    agent = MockAgent.new(turn_results: [
      { ok: true, event: :turn_completed },
      { ok: true, event: :turn_completed },
      { ok: true, event: :turn_completed },
    ])
    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Fix bug", state: "In Progress")
    ])

    runner = Symphony::AgentRunner.new(
      workspace: @workspace, agent: agent, config: @config,
      tracker: tracker, prompt_template: "Fix {{ issue.identifier }}"
    )
    result = runner.run(issue: @issue)

    assert result[:ok]
    assert_equal :max_turns_reached, result[:outcome]
    assert_equal 3, agent.turn_count
  end

  test "stops at max_turns" do
    config = Symphony::ServiceConfig.new({
      "agent" => { "max_turns" => 2 },
      "tracker" => { "active_states" => "Todo, In Progress" }
    })
    agent = MockAgent.new(turn_results: [
      { ok: true, event: :turn_completed },
      { ok: true, event: :turn_completed },
    ])
    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Fix bug", state: "Todo")
    ])

    runner = Symphony::AgentRunner.new(
      workspace: @workspace, agent: agent, config: config,
      tracker: tracker, prompt_template: "Fix {{ issue.identifier }}"
    )
    result = runner.run(issue: @issue)

    assert result[:ok]
    assert_equal :max_turns_reached, result[:outcome]
    assert_equal 2, agent.turn_count
  end

  test "returns error on turn failure" do
    agent = MockAgent.new(turn_results: [{ error: :turn_failed }])
    tracker = Symphony::Trackers::Memory.new(issues: [@issue])

    runner = Symphony::AgentRunner.new(
      workspace: @workspace, agent: agent, config: @config,
      tracker: tracker, prompt_template: "Fix {{ issue.identifier }}"
    )
    result = runner.run(issue: @issue)

    assert_equal :turn_failed, result[:error]
  end

  test "returns error on before_run hook failure" do
    ws = Symphony::Workspace.new(root: @root, hooks: { "before_run" => "exit 1" }, hooks_timeout_ms: 5000)
    agent = MockAgent.new(turn_results: [])
    tracker = Symphony::Trackers::Memory.new(issues: [@issue])

    runner = Symphony::AgentRunner.new(
      workspace: ws, agent: agent, config: @config,
      tracker: tracker, prompt_template: "Fix {{ issue.identifier }}"
    )
    # Need to prepare workspace first
    ws.prepare(@issue.identifier)
    result = runner.run(issue: @issue)

    assert_equal :before_run_hook_failed, result[:error]
  end

  test "emits events via on_event callback" do
    events = []
    agent = MockAgent.new(turn_results: [{ ok: true, event: :turn_completed }])
    tracker = Symphony::Trackers::Memory.new(issues: [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Fix bug", state: "Done")
    ])

    runner = Symphony::AgentRunner.new(
      workspace: @workspace, agent: agent, config: @config,
      tracker: tracker, prompt_template: "Fix {{ issue.identifier }}",
      on_event: ->(event) { events << event }
    )
    runner.run(issue: @issue)

    assert events.any?, "Expected events to be emitted"
  end

  # Minimal mock agent for unit testing AgentRunner
  class MockAgent < Symphony::Agents::Base
    attr_reader :turn_count, :stopped

    def initialize(turn_results: [])
      @turn_results = turn_results
      @turn_count = 0
      @stopped = false
    end

    def start_session(workspace_path:, config: nil)
      { ok: true, session: { mock: true } }
    end

    def run_turn(session:, prompt:, issue:, &on_message)
      result = @turn_results[@turn_count] || { ok: true, event: :turn_completed }
      @turn_count += 1
      on_message&.call({ event: :test_event, timestamp: Time.now.utc })
      result
    end

    def stop_session(session)
      @stopped = true
    end
  end
end
