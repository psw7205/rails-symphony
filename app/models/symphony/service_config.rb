module Symphony
  class ServiceConfig
    DEFAULT_ACTIVE_STATES = ["Todo", "In Progress"].freeze
    DEFAULT_TERMINAL_STATES = ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"].freeze
    DEFAULT_LINEAR_ENDPOINT = "https://api.linear.app/graphql".freeze

    def initialize(config)
      @config = config || {}
    end

    # Tracker
    def tracker_kind = dig("tracker", "kind")
    def tracker_endpoint = dig("tracker", "endpoint") || DEFAULT_LINEAR_ENDPOINT
    def tracker_project_slug = dig("tracker", "project_slug")

    def tracker_api_key
      raw = dig("tracker", "api_key")
      resolved = resolve_env_var(raw) || ENV["LINEAR_API_KEY"]
      resolved.nil? || resolved.empty? ? nil : resolved
    end

    def active_states
      parse_state_list(dig("tracker", "active_states"), DEFAULT_ACTIVE_STATES)
    end

    def terminal_states
      parse_state_list(dig("tracker", "terminal_states"), DEFAULT_TERMINAL_STATES)
    end

    # Polling
    def poll_interval_ms = integer_value("polling", "interval_ms", 30_000)

    # Workspace
    def workspace_root
      raw = dig("workspace", "root") || File.join(Dir.tmpdir, "symphony_workspaces")
      expand_path(resolve_env_var(raw) || raw)
    end

    # Hooks
    def hooks = @config.dig("hooks") || {}
    def hooks_timeout_ms = integer_value("hooks", "timeout_ms", 60_000).then { |v| v > 0 ? v : 60_000 }

    # Agent
    def max_concurrent_agents = integer_value("agent", "max_concurrent_agents", 10)
    def max_turns = integer_value("agent", "max_turns", 20)
    def max_retry_backoff_ms = integer_value("agent", "max_retry_backoff_ms", 300_000)

    def max_concurrent_agents_by_state
      raw = @config.dig("agent", "max_concurrent_agents_by_state") || {}
      raw.each_with_object({}) do |(state, limit), hash|
        int_limit = limit.to_i
        hash[state.to_s.strip.downcase] = int_limit if int_limit > 0
      end
    end

    def max_concurrent_agents_for_state(state_name)
      max_concurrent_agents_by_state[state_name.to_s.strip.downcase]
    end

    # Codex
    def codex_command = dig("codex", "command") || "codex app-server"
    def codex_turn_timeout_ms = integer_value("codex", "turn_timeout_ms", 3_600_000)
    def codex_read_timeout_ms = integer_value("codex", "read_timeout_ms", 5_000)
    def codex_stall_timeout_ms = integer_value("codex", "stall_timeout_ms", 300_000)
    def codex_approval_policy = dig("codex", "approval_policy")
    def codex_thread_sandbox = dig("codex", "thread_sandbox")
    def codex_turn_sandbox_policy = dig("codex", "turn_sandbox_policy")

    # Validation (SPEC 6.3)
    def validate!
      errors = []
      errors << "tracker.kind is required" unless tracker_kind
      errors << "tracker.kind '#{tracker_kind}' is not supported" if tracker_kind && tracker_kind != "linear"
      errors << "tracker.api_key is required" unless tracker_api_key
      errors << "tracker.project_slug is required" unless tracker_project_slug
      errors << "codex.command is required" if codex_command.to_s.strip.empty?

      errors.empty? ? :ok : { error: :validation_error, messages: errors }
    end

    private

      def dig(*keys) = @config.dig(*keys)

      def integer_value(section, key, default)
        raw = dig(section, key)
        return default if raw.nil?
        Integer(raw)
      rescue ArgumentError, TypeError
        default
      end

      def resolve_env_var(value)
        return value unless value.is_a?(String) && value.start_with?("$")
        env_name = value[1..]
        result = ENV[env_name]
        result.nil? || result.empty? ? nil : result
      end

      def expand_path(path)
        return path unless path.is_a?(String)
        File.expand_path(path)
      end

      def parse_state_list(raw, default)
        case raw
        when Array then raw.map(&:to_s)
        when String then raw.split(",").map(&:strip)
        else default
        end
      end
  end
end
