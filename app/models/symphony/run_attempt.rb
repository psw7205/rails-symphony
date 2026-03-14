module Symphony
  class RunAttempt < ApplicationRecord
    self.table_name = "symphony_run_attempts"

    belongs_to :persisted_issue, class_name: "Symphony::PersistedIssue", foreign_key: :issue_id
    has_one :agent_session, class_name: "Symphony::AgentSession"

    scope :chronologically, -> { order(created_at: :asc) }
    scope :latest_for_issue, ->(issue_id) { where(issue_id: issue_id).order(attempt: :desc).first }
  end
end
