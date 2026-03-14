require "test_helper"
require "tmpdir"

class SymphonyE2eTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("symphony_e2e")
    @workflow_file = File.join(@root, "WORKFLOW.md")
    @workspace_root = File.join(@root, "workspaces")
    FileUtils.mkdir_p(@workspace_root)

    File.write(@workflow_file, <<~WORKFLOW)
      ---
      tracker:
        kind: linear
        api_key: test-key
        project_slug: test-proj
      codex:
        command: echo
      workspace_root: #{@workspace_root}
      active_states: In Progress, Todo
      terminal_states: Done, Cancelled
      max_concurrent_agents: 2
      max_turns: 2
      poll_interval_ms: 60000
      ---
      You are working on {{ issue.identifier }}: {{ issue.title }}.
    WORKFLOW

    @store = Symphony::WorkflowStore.new(@workflow_file)
    @tracker = Symphony::Trackers::Memory.new
    @dispatched = []
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "full cycle: fetch → dispatch → worker exit → retry → re-dispatch" do
    # 1. Add candidate issues to memory tracker
    @tracker.add_issue(Symphony::Issue.new(
      id: "ISS-1", identifier: "PROJ-1", title: "First task",
      state: "In Progress", priority: 1, created_at: Time.now.utc
    ))
    @tracker.add_issue(Symphony::Issue.new(
      id: "ISS-2", identifier: "PROJ-2", title: "Second task",
      state: "In Progress", priority: 2, created_at: Time.now.utc
    ))

    workspace = Symphony::Workspace.new(root: @workspace_root)
    config = @store.service_config

    orchestrator = Symphony::Orchestrator.new(
      tracker: @tracker,
      workspace: workspace,
      agent: nil,
      workflow_store: @store,
      on_dispatch: ->(issue, attempt) { @dispatched << { id: issue.id, identifier: issue.identifier, attempt: attempt } }
    )

    # 2. First tick dispatches both issues (max_concurrent_agents: 2)
    orchestrator.tick

    assert_equal 2, orchestrator.running_count
    assert_equal 2, @dispatched.size
    assert_equal "ISS-1", @dispatched[0][:id]
    assert_equal "ISS-2", @dispatched[1][:id]

    # 3. Worker exits normally for ISS-1 → schedules 1s continuation retry
    orchestrator.on_worker_exit_normal("ISS-1", "PROJ-1")

    assert_equal 1, orchestrator.running_count
    assert orchestrator.retry_attempts.key?("ISS-1")
    assert_equal 1, orchestrator.retry_attempts["ISS-1"][:attempt]

    # 4. Worker exits abnormally for ISS-2 → schedules exponential backoff retry
    orchestrator.on_worker_exit_abnormal("ISS-2", "PROJ-2", attempt: 1, error: "agent_crash")

    assert_equal 0, orchestrator.running_count
    assert orchestrator.retry_attempts.key?("ISS-2")
    assert_equal 1, orchestrator.retry_attempts["ISS-2"][:attempt]

    # 5. Simulate retry timer for ISS-1 → re-dispatches
    orchestrator.on_retry_timer("ISS-1")

    assert_equal 1, orchestrator.running_count
    assert_equal 3, @dispatched.size
    assert_equal "ISS-1", @dispatched[2][:id]
    assert_equal 1, @dispatched[2][:attempt] # continuation attempt
  end

  test "dispatch respects blocker check for Todo issues" do
    blocked = Symphony::Issue.new(
      id: "ISS-3", identifier: "PROJ-3", title: "Blocked todo",
      state: "Todo", priority: 1, created_at: Time.now.utc,
      blocked_by: [{ "id" => "ISS-4", "identifier" => "PROJ-4", "state" => "In Progress" }]
    )
    unblocked = Symphony::Issue.new(
      id: "ISS-5", identifier: "PROJ-5", title: "Free todo",
      state: "Todo", priority: 2, created_at: Time.now.utc
    )

    @tracker.add_issue(blocked)
    @tracker.add_issue(unblocked)

    workspace = Symphony::Workspace.new(root: @workspace_root)

    orchestrator = Symphony::Orchestrator.new(
      tracker: @tracker,
      workspace: workspace,
      agent: nil,
      workflow_store: @store,
      on_dispatch: ->(issue, attempt) { @dispatched << issue.id }
    )

    orchestrator.tick

    # Only unblocked issue dispatched
    assert_equal ["ISS-5"], @dispatched
  end

  test "reconciliation removes terminal issues from running" do
    issue = Symphony::Issue.new(
      id: "ISS-6", identifier: "PROJ-6", title: "Will be done",
      state: "In Progress", priority: 1, created_at: Time.now.utc
    )
    @tracker.add_issue(issue)

    workspace = Symphony::Workspace.new(root: @workspace_root)

    orchestrator = Symphony::Orchestrator.new(
      tracker: @tracker,
      workspace: workspace,
      agent: nil,
      workflow_store: @store,
      on_dispatch: ->(issue, attempt) { @dispatched << issue.id }
    )

    orchestrator.tick
    assert_equal 1, orchestrator.running_count

    # Simulate tracker state change to terminal
    @tracker.update_issue_state("ISS-6", "Done")

    # Next tick triggers reconciliation
    orchestrator.tick
    assert_equal 0, orchestrator.running_count
  end

  test "prompt builder renders issue context from workflow template" do
    config = @store.service_config
    issue = Symphony::Issue.new(
      id: "ISS-7", identifier: "PROJ-7", title: "Test rendering", state: "In Progress"
    )

    prompt = Symphony::PromptBuilder.render(
      @store.prompt_template,
      issue: issue,
      attempt: 1
    )

    assert_includes prompt, "PROJ-7"
    assert_includes prompt, "Test rendering"
  end

  test "workspace prepare and remove lifecycle" do
    workspace = Symphony::Workspace.new(root: @workspace_root)

    result = workspace.prepare("PROJ-8")
    assert result[:ok]
    assert Dir.exist?(result[:path])

    workspace.remove("PROJ-8")
    refute Dir.exist?(result[:path])
  end

  test "agent runner with mock agent completes turn loop" do
    mock_agent = MockAgent.new(turn_results: [{ ok: true }])

    workspace = Symphony::Workspace.new(root: @workspace_root)
    config = @store.service_config

    # Issue that becomes terminal after 1 turn
    issue = Symphony::Issue.new(
      id: "ISS-9", identifier: "PROJ-9", title: "Quick fix",
      state: "In Progress", priority: 1
    )

    # Tracker returns Done state after first turn
    @tracker.add_issue(issue)
    @tracker.update_issue_state("ISS-9", "Done")

    runner = Symphony::AgentRunner.new(
      workspace: workspace,
      agent: mock_agent,
      config: config,
      tracker: @tracker,
      prompt_template: @store.prompt_template
    )

    result = runner.run(issue: issue)

    assert result[:ok]
    assert_equal :completed, result[:outcome]
    assert_equal 1, mock_agent.turns_run
    assert mock_agent.session_stopped?
  end

  class MockAgent
    attr_reader :turns_run

    def initialize(turn_results:)
      @turn_results = turn_results
      @turns_run = 0
      @stopped = false
    end

    def start_session(workspace_path:, config:)
      { ok: true, session: { id: "mock-session" } }
    end

    def run_turn(session:, prompt:, issue:, &block)
      result = @turn_results[@turns_run] || { ok: true }
      @turns_run += 1
      result
    end

    def stop_session(session)
      @stopped = true
    end

    def session_stopped?
      @stopped
    end
  end
end
