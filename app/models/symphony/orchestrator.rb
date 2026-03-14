module Symphony
  class Orchestrator
    attr_reader :running, :claimed, :retry_attempts

    def initialize(tracker:, workspace:, agent:, workflow_store:, on_dispatch: nil)
      @tracker = tracker
      @workspace = workspace
      @agent = agent
      @workflow_store = workflow_store
      @on_dispatch = on_dispatch
      @running = {}     # issue_id => RunningEntry
      @claimed = Set.new
      @retry_attempts = {} # issue_id => RetryEntry
      @codex_totals = { input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0.0 }
      @codex_rate_limits = nil
      @mutex = Mutex.new
    end

    def config
      @workflow_store.service_config
    end

    # Main poll tick (SPEC 8.1)
    def tick
      @mutex.synchronize do
        reconcile_running_issues
        return unless validate_dispatch_config

        result = @tracker.fetch_candidate_issues(active_states: config.active_states)
        unless result[:ok]
          Rails.logger.error("[Orchestrator] Failed to fetch candidates: #{result.inspect}")
          return
        end

        candidates = sort_for_dispatch(result[:issues])
        dispatch_eligible(candidates)
      end
    end

    # Called when a worker exits normally
    def on_worker_exit_normal(issue_id, issue_identifier)
      @mutex.synchronize do
        accumulate_runtime(issue_id)
        @running.delete(issue_id)
        schedule_retry(issue_id, issue_identifier, attempt: 1, delay_ms: 1000)
      end
    end

    # Called when a worker exits abnormally
    def on_worker_exit_abnormal(issue_id, issue_identifier, attempt:, error: nil)
      @mutex.synchronize do
        accumulate_runtime(issue_id)
        @running.delete(issue_id)
        delay = failure_backoff_ms(attempt)
        schedule_retry(issue_id, issue_identifier, attempt: attempt, delay_ms: delay, error: error)
      end
    end

    # Called when a retry timer fires
    def on_retry_timer(issue_id)
      @mutex.synchronize do
        entry = @retry_attempts.delete(issue_id)
        return release_claim(issue_id) unless entry

        result = @tracker.fetch_candidate_issues(active_states: config.active_states)
        unless result[:ok]
          Rails.logger.warn("[Orchestrator] Retry fetch failed for #{issue_id}, releasing")
          return release_claim(issue_id)
        end

        issue = result[:issues].find { |i| i.id == issue_id }
        unless issue
          return release_claim(issue_id)
        end

        if dispatch_slots_available?(issue.state)
          do_dispatch(issue, attempt: entry[:attempt])
        else
          schedule_retry(issue_id, entry[:identifier], attempt: entry[:attempt],
                         delay_ms: failure_backoff_ms(entry[:attempt]), error: "no available orchestrator slots")
        end
      end
    end

    # Called by agent worker with codex events
    def handle_codex_update(issue_id, event)
      @mutex.synchronize do
        entry = @running[issue_id]
        return unless entry
        entry[:last_codex_event] = event[:event]
        entry[:last_codex_timestamp] = event[:timestamp] || Time.now.utc

        if event[:rate_limits]
          @codex_rate_limits = event[:rate_limits]
        end

        if event[:usage]
          @codex_totals[:input_tokens] += (event[:usage][:input_tokens] || 0)
          @codex_totals[:output_tokens] += (event[:usage][:output_tokens] || 0)
          @codex_totals[:total_tokens] += (event[:usage][:total_tokens] || 0)
        end
      end
    end

    def running_count
      @running.size
    end

    # SPEC 13.3: Synchronous runtime snapshot for dashboards/API
    def snapshot
      @mutex.synchronize do
        now_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000

        running_rows = @running.map do |issue_id, entry|
          elapsed_s = (now_ms - entry[:started_at]) / 1000.0
          {
            issue_id: issue_id,
            issue_identifier: entry[:identifier],
            state: entry[:issue]&.state,
            started_at: entry[:wall_started_at],
            last_codex_event: entry[:last_codex_event],
            last_codex_timestamp: entry[:last_codex_timestamp],
            elapsed_seconds: elapsed_s.round(1),
            attempt: entry[:attempt]
          }
        end

        retry_rows = @retry_attempts.map do |issue_id, entry|
          {
            issue_id: issue_id,
            issue_identifier: entry[:identifier],
            attempt: entry[:attempt],
            due_at: entry[:due_at]&.iso8601,
            error: entry[:error]
          }
        end

        active_elapsed = running_rows.sum { |r| r[:elapsed_seconds] }

        {
          generated_at: Time.now.utc.iso8601,
          counts: { running: running_rows.size, retrying: retry_rows.size },
          running: running_rows,
          retrying: retry_rows,
          codex_totals: {
            input_tokens: @codex_totals[:input_tokens],
            output_tokens: @codex_totals[:output_tokens],
            total_tokens: @codex_totals[:total_tokens],
            seconds_running: (@codex_totals[:seconds_running] + active_elapsed).round(1)
          },
          rate_limits: @codex_rate_limits
        }
      end
    end

    # SPEC 13.7.2: Trigger immediate poll+reconcile
    def request_refresh
      tick
      {
        queued: true,
        coalesced: false,
        requested_at: Time.now.utc.iso8601,
        operations: %w[poll reconcile]
      }
    end

    private

      def reconcile_running_issues
        return if @running.empty?

        # Part A: Stall detection
        stall_timeout = config.codex_stall_timeout_ms
        if stall_timeout > 0
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000
          @running.each do |issue_id, entry|
            reference = entry[:last_codex_timestamp] || entry[:started_at]
            elapsed = now - (reference.is_a?(Time) ? reference.to_f * 1000 : reference)
            if elapsed > stall_timeout
              Rails.logger.warn("[Orchestrator] Stall detected for #{issue_id}, elapsed=#{elapsed.round}ms")
              @running.delete(issue_id)
              schedule_retry(issue_id, entry[:identifier], attempt: (entry[:attempt] || 0) + 1,
                             delay_ms: failure_backoff_ms((entry[:attempt] || 0) + 1), error: "stall_timeout")
            end
          end
        end

        # Part B: Tracker state refresh
        ids = @running.keys
        return if ids.empty?

        result = @tracker.fetch_issue_states_by_ids(ids)
        unless result[:ok]
          Rails.logger.warn("[Orchestrator] Reconciliation state refresh failed, skipping")
          return
        end

        refreshed = result[:issues].index_by(&:id)
        terminal = config.terminal_states.map { |s| s.strip.downcase }
        active = config.active_states.map { |s| s.strip.downcase }

        ids.each do |issue_id|
          entry = @running[issue_id]
          next unless entry

          issue = refreshed[issue_id]
          state = issue&.state.to_s.strip.downcase

          if issue.nil? || terminal.include?(state)
            @running.delete(issue_id)
            @workspace.remove(entry[:identifier]) if issue && terminal.include?(state)
            release_claim(issue_id)
          elsif active.include?(state)
            # Still active, update snapshot
          else
            # Non-active, non-terminal
            @running.delete(issue_id)
            release_claim(issue_id)
          end
        end
      end

      def validate_dispatch_config
        result = config.validate!
        if result != :ok
          Rails.logger.warn("[Orchestrator] Config validation failed: #{result[:messages]&.join(', ')}")
          return false
        end
        true
      end

      def sort_for_dispatch(issues)
        issues.sort_by do |i|
          [i.priority || 999, i.created_at || Time.at(0), i.identifier.to_s]
        end
      end

      def dispatch_eligible(candidates)
        candidates.each do |issue|
          break unless global_slots_available?
          next if @claimed.include?(issue.id) || @running.key?(issue.id)
          next unless dispatch_slots_available?(issue.state)
          next if blocked_todo?(issue)

          do_dispatch(issue)
        end
      end

      def do_dispatch(issue, attempt: nil)
        @claimed.add(issue.id)
        @running[issue.id] = {
          identifier: issue.identifier,
          issue: issue,
          started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000,
          wall_started_at: Time.now.utc.iso8601,
          last_codex_event: nil,
          last_codex_timestamp: nil,
          attempt: attempt
        }

        Rails.logger.info("[Orchestrator] Dispatching #{issue.identifier} (#{issue.id})")
        @on_dispatch&.call(issue, attempt)
      end

      def global_slots_available?
        @running.size < config.max_concurrent_agents
      end

      def dispatch_slots_available?(state)
        return false unless global_slots_available?

        per_state_limit = config.max_concurrent_agents_for_state(state)
        return true unless per_state_limit

        running_in_state = @running.values.count { |e| e[:issue]&.state.to_s.strip.downcase == state.to_s.strip.downcase }
        running_in_state < per_state_limit
      end

      def blocked_todo?(issue)
        return false unless issue.state.to_s.strip.downcase == "todo"
        issue.has_non_terminal_blockers?(config.terminal_states)
      end

      def schedule_retry(issue_id, identifier, attempt:, delay_ms:, error: nil)
        @retry_attempts.delete(issue_id)
        @retry_attempts[issue_id] = {
          identifier: identifier,
          attempt: attempt,
          delay_ms: delay_ms,
          due_at: Time.now.utc + (delay_ms / 1000.0),
          error: error
        }
        @claimed.add(issue_id)
      end

      def accumulate_runtime(issue_id)
        entry = @running[issue_id]
        return unless entry
        now_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000
        elapsed_s = (now_ms - entry[:started_at]) / 1000.0
        @codex_totals[:seconds_running] += elapsed_s
      end

      def release_claim(issue_id)
        @claimed.delete(issue_id)
        @retry_attempts.delete(issue_id)
        @running.delete(issue_id)
      end

      def failure_backoff_ms(attempt)
        base = 10_000 * (2**(attempt - 1))
        [base, config.max_retry_backoff_ms].min
      end
  end
end
