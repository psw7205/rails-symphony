module Symphony
  class ManagedWorkflow < ApplicationRecord
    self.table_name = "symphony_managed_workflows"

    STATUSES = %w[active inactive].freeze

    belongs_to :managed_project, class_name: "Symphony::ManagedProject"
    belongs_to :tracker_connection, class_name: "Symphony::TrackerConnection"
    belongs_to :agent_connection, class_name: "Symphony::AgentConnection"
    has_many :managed_issues, class_name: "Symphony::ManagedIssue", foreign_key: :managed_workflow_id

    validates :name, :slug, :status, presence: true
    validates :slug, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
  end
end
