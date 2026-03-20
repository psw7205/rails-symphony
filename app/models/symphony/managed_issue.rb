module Symphony
  class ManagedIssue < ApplicationRecord
    self.table_name = "symphony_managed_issues"

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow"
  end
end
