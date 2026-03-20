module Symphony
  class RetryEntry < ApplicationRecord
    self.table_name = "symphony_retry_entries"

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow", optional: true

    scope :due, -> { where("due_at <= ?", Time.current) }
  end
end
