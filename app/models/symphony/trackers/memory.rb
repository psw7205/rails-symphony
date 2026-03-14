module Symphony
  module Trackers
    class Memory < Base
      def initialize(issues: [])
        @issues = issues
      end

      def fetch_candidate_issues(active_states:)
        normalized = active_states.map { |s| s.to_s.strip.downcase }
        filtered = @issues.select { |i| normalized.include?(i.state.to_s.strip.downcase) }
        { ok: true, issues: filtered }
      end

      def fetch_issue_states_by_ids(ids)
        id_set = ids.to_set
        filtered = @issues.select { |i| id_set.include?(i.id) }
        { ok: true, issues: filtered }
      end

      def fetch_issues_by_states(states)
        return { ok: true, issues: [] } if states.empty?
        normalized = states.map { |s| s.to_s.strip.downcase }
        filtered = @issues.select { |i| normalized.include?(i.state.to_s.strip.downcase) }
        { ok: true, issues: filtered }
      end
    end
  end
end
