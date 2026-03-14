module Symphony
  class OrchestratorState < ApplicationRecord
    self.table_name = "symphony_orchestrator_states"

    def self.current
      first_or_create!
    end
  end
end
