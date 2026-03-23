module Symphony
  module Trackers
    class Database < Base
      def initialize(managed_workflow:)
        @managed_workflow = managed_workflow
      end

      def capabilities
        super + [ :create_issue, :update_issue, :transition_issue ]
      end

      def fetch_candidate_issues(active_states:)
        fetch_issues_by_states(active_states)
      end

      def fetch_issue_states_by_ids(ids)
        normalized_ids = ids.map(&:to_s)
        records = scoped_managed_issues.select { |issue| normalized_ids.include?(issue.id.to_s) }
        { ok: true, issues: records.map { |record| to_issue(record) } }
      end

      def fetch_issues_by_states(states)
        return { ok: true, issues: [] } if states.empty?

        normalized_states = states.map { |state| state.to_s.strip.downcase }
        records = scoped_managed_issues.select do |issue|
          normalized_states.include?(issue.state.to_s.strip.downcase)
        end
        { ok: true, issues: records.map { |record| to_issue(record) } }
      end

      private
        def scoped_managed_issues
          Symphony::ManagedIssue.where(managed_workflow_id: @managed_workflow.id).order(:id)
        end

        def to_issue(record)
          Symphony::Issue.new(
            id: record.id.to_s,
            identifier: record.identifier,
            title: record.title,
            description: record.description,
            priority: record.priority&.to_i,
            state: record.state,
            labels: record.labels || [],
            blocked_by: record.blocked_by || [],
            created_at: record.created_at,
            updated_at: record.updated_at
          )
        end
    end
  end
end
