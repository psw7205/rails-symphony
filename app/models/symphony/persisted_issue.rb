module Symphony
  class PersistedIssue < ApplicationRecord
    self.table_name = "symphony_issues"

    has_many :run_attempts, class_name: "Symphony::RunAttempt", foreign_key: :issue_id

    scope :by_state, ->(state) { where(state: state) }
    scope :active, -> { where(state: ServiceConfig::DEFAULT_ACTIVE_STATES) }
  end
end
