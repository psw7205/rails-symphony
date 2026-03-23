module Symphony
  class TrackerConnection < ApplicationRecord
    self.table_name = "symphony_tracker_connections"

    STATUSES = %w[active inactive].freeze

    attr_accessor :config_json

    validates :name, :kind, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end
