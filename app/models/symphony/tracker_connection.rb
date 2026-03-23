module Symphony
  class TrackerConnection < ApplicationRecord
    self.table_name = "symphony_tracker_connections"

    STATUSES = %w[active inactive].freeze

    attr_accessor :config_json

    validates :name, :kind, :status, presence: true
    validates :status, inclusion: { in: STATUSES }

    def tracker_setting(key)
      tracker_settings[key.to_s]
    end

    def resolved_tracker_setting(key)
      value = tracker_setting(key)
      return value unless value.is_a?(String) && value.start_with?("$")

      ENV[value.delete_prefix("$")]
    end

    private
      def tracker_settings
        raw = config.is_a?(Hash) ? config.deep_stringify_keys : {}
        raw.key?("tracker") ? raw.fetch("tracker", {}) : raw
      end
  end
end
