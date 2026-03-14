module Symphony
  mattr_accessor :orchestrator, :tracker, :workspace, :agent, :workflow_store

  def self.config
    workflow_store&.service_config
  end

  def self.boot!(workflow_path:, logs_root: nil, port: nil)
    Rails.logger.info("[Symphony] Booting with workflow=#{workflow_path}")

    # 1. Load and validate workflow
    self.workflow_store = WorkflowStore.new(workflow_path)
    cfg = config

    validation = cfg.validate!
    unless validation == :ok
      Rails.logger.error("[Symphony] Config validation failed: #{validation[:messages]&.join(', ')}")
      raise "Symphony config validation failed: #{validation[:messages]&.join(', ')}"
    end

    # 2. Initialize components
    self.workspace = Workspace.new(
      root: cfg.workspace_root,
      hooks: cfg.hooks,
      hooks_timeout_ms: cfg.hooks_timeout_ms
    )

    self.tracker = build_tracker(cfg)
    self.agent = Agents::Codex.new(config: cfg)

    # 3. Startup terminal workspace cleanup
    cleanup_terminal_workspaces(cfg)

    # 4. Initialize orchestrator
    self.orchestrator = Orchestrator.new(
      tracker: tracker,
      workspace: workspace,
      agent: agent,
      workflow_store: workflow_store,
      on_dispatch: method(:dispatch_agent_worker)
    )

    # 5. Start file watcher
    start_file_watcher(workflow_path)

    # 6. Run initial tick
    orchestrator.tick

    Rails.logger.info("[Symphony] Boot complete. Polling every #{cfg.poll_interval_ms}ms")

    # Block on Solid Queue (if running as CLI)
    if $PROGRAM_NAME.end_with?("symphony")
      start_poll_loop(cfg.poll_interval_ms)
    end
  end

  def self.build_tracker(cfg)
    case cfg.tracker_kind
    when "linear"
      Trackers::Linear.new(
        api_key: cfg.tracker_api_key,
        endpoint: cfg.tracker_endpoint,
        project_slug: cfg.tracker_project_slug
      )
    else
      raise "Unsupported tracker kind: #{cfg.tracker_kind}"
    end
  end

  def self.cleanup_terminal_workspaces(cfg)
    result = tracker.fetch_issues_by_states(cfg.terminal_states)
    if result[:ok]
      result[:issues].each do |issue|
        workspace.remove(issue.identifier)
        Rails.logger.info("[Symphony] Cleaned terminal workspace for #{issue.identifier}")
      end
    else
      Rails.logger.warn("[Symphony] Terminal cleanup fetch failed, continuing: #{result.inspect}")
    end
  end

  def self.dispatch_agent_worker(issue, attempt)
    AgentWorkerJob.perform_later(
      issue_id: issue.id,
      issue_identifier: issue.identifier,
      issue_title: issue.title,
      issue_state: issue.state,
      attempt: attempt
    )
  end

  def self.start_file_watcher(workflow_path)
    dir = File.dirname(workflow_path)
    filename = File.basename(workflow_path)

    @listener = Listen.to(dir, only: /#{Regexp.escape(filename)}$/) do |modified, added, _removed|
      if (modified + added).any?
        Rails.logger.info("[Symphony] Workflow file changed, reloading")
        workflow_store.reload_if_changed!
      end
    end
    @listener.start
  end

  def self.start_poll_loop(interval_ms)
    interval_sec = interval_ms / 1000.0
    Rails.logger.info("[Symphony] Starting poll loop (interval=#{interval_sec}s)")

    loop do
      sleep(interval_sec)
      orchestrator.tick

      # Process due retries
      now = Time.now.utc
      orchestrator.retry_attempts.select { |_, e| e[:due_at] && e[:due_at] <= now }.each_key do |issue_id|
        orchestrator.on_retry_timer(issue_id)
      end
    rescue Interrupt
      Rails.logger.info("[Symphony] Shutting down")
      @listener&.stop
      break
    rescue => e
      Rails.logger.error("[Symphony] Poll loop error: #{e.message}")
    end
  end

  private_class_method :build_tracker, :cleanup_terminal_workspaces,
                       :dispatch_agent_worker, :start_file_watcher, :start_poll_loop
end
