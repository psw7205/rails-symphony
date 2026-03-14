module Symphony
  class AgentRunner
    CONTINUATION_GUIDANCE = <<~PROMPT
      Continuation guidance:

      - The previous Codex turn completed normally, but the issue is still in an active state.
      - This is continuation turn #%<turn>d of %<max>d for the current agent run.
      - Resume from the current workspace state instead of restarting from scratch.
      - The original task instructions and prior turn context are already present in this thread.
      - Focus on the remaining ticket work.
    PROMPT

    def initialize(workspace:, agent:, config:, tracker:, prompt_template:, on_event: nil)
      @workspace = workspace
      @agent = agent
      @config = config
      @tracker = tracker
      @prompt_template = prompt_template
      @on_event = on_event
    end

    def run(issue:, attempt: nil)
      result = @workspace.prepare(issue.identifier)
      unless result[:ok]
        Rails.logger.error("[AgentRunner] Workspace prepare failed issue=#{issue.identifier}: #{result.inspect}")
        return { error: :workspace_failed, details: result }
      end

      hook_result = @workspace.run_before_run_hook(issue.identifier)
      if hook_result.is_a?(Hash) && hook_result[:error]
        return { error: :before_run_hook_failed, details: hook_result }
      end

      run_agent_turns(issue, attempt, result[:path])
    ensure
      @workspace.run_after_run_hook(issue.identifier) if result && result[:ok]
    end

    private

      def run_agent_turns(issue, attempt, workspace_path)
        session_result = @agent.start_session(workspace_path: workspace_path, config: @config)
        unless session_result[:ok]
          return { error: :session_start_failed, details: session_result }
        end

        session = session_result[:session]
        max_turns = @config.max_turns
        current_issue = issue

        begin
          (1..max_turns).each do |turn_number|
            prompt = build_prompt(current_issue, attempt, turn_number, max_turns)

            turn_result = @agent.run_turn(
              session: session,
              prompt: prompt,
              issue: current_issue
            ) { |event| @on_event&.call(event) }

            unless turn_result[:ok]
              return { error: turn_result[:error] || :turn_failed, details: turn_result }
            end

            break if turn_number >= max_turns

            continuation = check_continuation(current_issue)
            case continuation[:status]
            when :continue
              current_issue = continuation[:issue]
            when :done
              return { ok: true, outcome: :completed }
            when :error
              return { error: :issue_refresh_failed, details: continuation }
            end
          end

          { ok: true, outcome: :max_turns_reached }
        ensure
          @agent.stop_session(session)
        end
      rescue PromptBuilder::RenderError => e
        { error: :prompt_render_failed, message: e.message }
      end

      def build_prompt(issue, attempt, turn_number, max_turns)
        if turn_number == 1
          PromptBuilder.render(@prompt_template, issue: issue, attempt: attempt)
        else
          format(CONTINUATION_GUIDANCE, turn: turn_number, max: max_turns)
        end
      end

      def check_continuation(issue)
        result = @tracker.fetch_issue_states_by_ids([ issue.id ])
        unless result[:ok]
          return { status: :error, details: result }
        end

        refreshed = result[:issues].first
        return { status: :done } unless refreshed

        active = @config.active_states.map { |s| s.strip.downcase }
        if active.include?(refreshed.state.to_s.strip.downcase)
          { status: :continue, issue: refreshed }
        else
          { status: :done }
        end
      end
  end
end
