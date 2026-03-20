module Symphony
  class ManagedWorkflow < ApplicationRecord
    self.table_name = "symphony_managed_workflows"

    belongs_to :managed_project, class_name: "Symphony::ManagedProject"
    belongs_to :tracker_connection, class_name: "Symphony::TrackerConnection"
    belongs_to :agent_connection, class_name: "Symphony::AgentConnection"

    validates :name, :slug, :status, presence: true
  end
end
