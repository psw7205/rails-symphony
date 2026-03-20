module Symphony
  class PersistedIssue < ApplicationRecord
    self.table_name = "symphony_issues"

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow", optional: true
    has_many :run_attempts, class_name: "Symphony::RunAttempt", foreign_key: :issue_id

    validates :source_issue_id, uniqueness: { scope: :managed_workflow_id }, allow_nil: true

    scope :by_state, ->(state) { where(state: state) }
    scope :active, -> { where(state: ServiceConfig::DEFAULT_ACTIVE_STATES) }
  end
end
