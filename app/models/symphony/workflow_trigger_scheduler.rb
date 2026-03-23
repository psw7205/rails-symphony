module Symphony
  class WorkflowTriggerScheduler
    def self.enqueue(workflow_id:, source:, provider: nil, delivery_id: nil, metadata: {}, signature_state: nil)
      new(
        workflow_id: workflow_id,
        source: source,
        provider: provider,
        delivery_id: delivery_id,
        metadata: metadata,
        signature_state: signature_state
      ).enqueue
    end

    def initialize(workflow_id:, source:, provider:, delivery_id:, metadata:, signature_state:)
      @workflow_id = workflow_id.to_i
      @source = source
      @provider = provider
      @delivery_id = delivery_id
      @metadata = metadata || {}
      @signature_state = signature_state || default_signature_state
    end

    def enqueue
      if duplicate_delivery? || overlapping_open_request?
        event = create_event!(status: "ignored_duplicate")
        persist_trigger_summary(event)
        return build_result(event, queued: false, coalesced: true)
      end

      event = create_event!(status: "accepted")
      persist_trigger_summary(event)
      WorkflowPollJob.perform_later(workflow_id: @workflow_id, trigger_event_id: event.id)
      event.update!(status: "enqueued")
      persist_trigger_summary(event)
      build_result(event, queued: true, coalesced: false)
    rescue => error
      if event&.persisted?
        event.update!(
          status: "failed",
          error: error.message,
          finished_at: Time.current
        )
        OrchestratorState.record_tick_finish!(
          workflow_id: @workflow_id,
          source: @source,
          trigger_event: event,
          finished_at: event.finished_at,
          status: "failed",
          error: error.message
        )
      end

      raise
    end

    private
      def duplicate_delivery?
        WorkflowTriggerEvent.duplicate_delivery?(
          managed_workflow_id: @workflow_id,
          provider: @provider,
          delivery_id: @delivery_id
        )
      end

      def overlapping_open_request?
        return false if webhook_source?

        WorkflowTriggerEvent.open_requests.where(managed_workflow_id: @workflow_id).exists?
      end

      def webhook_source?
        @source.to_s.start_with?("webhook_")
      end

      def create_event!(status:)
        WorkflowTriggerEvent.create!(
          managed_workflow_id: @workflow_id,
          source: @source,
          provider: @provider,
          delivery_id: @delivery_id,
          status: status,
          signature_state: @signature_state,
          requested_at: Time.current,
          metadata: @metadata
        )
      end

      def persist_trigger_summary(event)
        OrchestratorState.record_trigger!(
          workflow_id: @workflow_id,
          source: @source,
          requested_at: event.requested_at,
          trigger_event: event
        )
      end

      def build_result(event, queued:, coalesced:)
        {
          queued: queued,
          coalesced: coalesced,
          trigger_event_id: event.id,
          source: event.source,
          requested_at: event.requested_at.iso8601
        }
      end

      def default_signature_state
        webhook_source? ? nil : "not_applicable"
      end
  end
end
