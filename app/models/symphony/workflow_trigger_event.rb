module Symphony
  class WorkflowTriggerEvent < ApplicationRecord
    self.table_name = "symphony_workflow_trigger_events"

    SOURCES = %w[poll manual_refresh database_write webhook_github webhook_linear].freeze
    STATUSES = %w[accepted ignored_duplicate ignored_unsupported rejected_signature enqueued running succeeded failed].freeze
    SIGNATURE_STATES = %w[not_applicable verified missing invalid].freeze
    OPEN_STATUSES = %w[accepted enqueued running].freeze
    FAILURE_STATUSES = %w[rejected_signature failed].freeze
    ACCEPTED_STATUSES = %w[accepted enqueued running succeeded].freeze

    belongs_to :managed_workflow, class_name: "Symphony::ManagedWorkflow"

    validates :managed_workflow, :source, :status, :requested_at, presence: true
    validates :source, inclusion: { in: SOURCES }
    validates :status, inclusion: { in: STATUSES }
    validates :signature_state, inclusion: { in: SIGNATURE_STATES }, allow_nil: true

    scope :recent_failures, -> { where(status: FAILURE_STATUSES).order(requested_at: :desc) }
    scope :recent_accepted, -> { where(status: ACCEPTED_STATUSES).order(requested_at: :desc) }
    scope :unresolved_failures, -> { where(status: FAILURE_STATUSES).order(requested_at: :desc) }
    scope :open_requests, -> { where(status: OPEN_STATUSES) }

    def self.duplicate_delivery?(managed_workflow_id:, provider:, delivery_id:)
      return false if managed_workflow_id.blank? || provider.blank? || delivery_id.blank?

      where(
        managed_workflow_id: managed_workflow_id,
        provider: provider,
        delivery_id: delivery_id
      ).exists?
    end
  end
end
