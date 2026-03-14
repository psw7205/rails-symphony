module Symphony
  class RetryEntry < ApplicationRecord
    self.table_name = "symphony_retry_entries"

    scope :due, -> { where("due_at <= ?", Time.current) }
  end
end
