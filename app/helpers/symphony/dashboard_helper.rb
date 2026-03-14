module Symphony
  module DashboardHelper
    def format_runtime(seconds)
      seconds = (seconds || 0).to_f.round
      mins = seconds / 60
      secs = seconds % 60
      "#{mins}m #{secs}s"
    end

    def state_badge_class(state)
      normalized = state.to_s.downcase
      case
      when normalized.match?(/progress|running|active/) then "state-badge-active"
      when normalized.match?(/blocked|error|failed/) then "state-badge-danger"
      when normalized.match?(/todo|queued|pending|retry/) then "state-badge-warning"
      else ""
      end
    end
  end
end
