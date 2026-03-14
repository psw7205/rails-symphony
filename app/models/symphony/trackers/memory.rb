module Symphony
  module Trackers
    class Memory < Base
      attr_reader :issues

      def initialize(issues: [])
        @issues = issues
      end

      def add_issue(issue)
        @issues << issue
      end

      def update_issue_state(id, new_state)
        idx = @issues.index { |i| i.id == id }
        return unless idx

        old = @issues[idx]
        @issues[idx] = Issue.new(
          id: old.id, identifier: old.identifier, title: old.title,
          state: new_state, description: old.description, priority: old.priority,
          branch_name: old.branch_name, url: old.url, labels: old.labels,
          blocked_by: old.blocked_by, created_at: old.created_at, updated_at: old.updated_at
        )
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
