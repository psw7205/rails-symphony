module Symphony
  class ManagedProject < ApplicationRecord
    self.table_name = "symphony_managed_projects"

    STATUSES = %w[active inactive].freeze

    validates :name, :slug, :status, presence: true
    validates :slug, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
  end
end
