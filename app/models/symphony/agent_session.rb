module Symphony
  class AgentSession < ApplicationRecord
    self.table_name = "symphony_agent_sessions"

    belongs_to :run_attempt, class_name: "Symphony::RunAttempt"
  end
end
