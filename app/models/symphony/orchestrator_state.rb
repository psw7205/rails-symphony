module Symphony
  class OrchestratorState < ApplicationRecord
    self.table_name = "symphony_orchestrator_states"

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow", optional: true

    def self.for_workflow!(managed_workflow_id)
      find_or_create_by!(managed_workflow_id: managed_workflow_id)
    end

    # Legacy file-mode singleton accessor. Managed mode should use for_workflow!.
    def self.current
      first_or_create!
    end
  end
end
