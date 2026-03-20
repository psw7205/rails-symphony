module Symphony
  class ManagedIssue < ApplicationRecord
    # Database tracker workflows own their issue ledger in this table.
    self.table_name = "symphony_managed_issues"

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow"

    validate :managed_workflow_uses_database_tracker

    private
      def managed_workflow_uses_database_tracker
        return if managed_workflow.blank?
        return if managed_workflow.tracker_connection&.kind == "database"

        errors.add(:managed_workflow, "must use a database tracker connection")
      end
  end
end
