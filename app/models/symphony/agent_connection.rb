module Symphony
  class AgentConnection < ApplicationRecord
    self.table_name = "symphony_agent_connections"

    STATUSES = %w[active inactive].freeze

    validates :name, :kind, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end
