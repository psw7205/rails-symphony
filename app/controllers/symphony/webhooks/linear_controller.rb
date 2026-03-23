module Symphony
  module Webhooks
    class LinearController < ApplicationController
      skip_forgery_protection

      def create
        render_result(process_webhook(
          provider: "linear",
          source: "webhook_linear",
          event_type: request.headers["Linear-Event"],
          delivery_id: request.headers["Linear-Delivery"]
        ))
      end

      private
        def process_webhook(provider:, source:, event_type:, delivery_id:)
          raw_body = request.raw_post
          payload = parse_payload(raw_body)
          route = WorkflowWebhookRouter.route(provider: provider, event_type: event_type, payload: payload)
          results = route[:workflows].map do |workflow|
            process_workflow(
              workflow: workflow,
              provider: provider,
              source: source,
              raw_body: raw_body,
              payload: payload,
              event_type: event_type,
              delivery_id: delivery_id,
              ignored: route[:ignored],
              reason: route[:reason]
            )
          end

          {
            queued_count: results.count { |result| result[:status] == :queued },
            coalesced_count: results.count { |result| result[:status] == :coalesced },
            rejected_count: results.count { |result| result[:status] == :rejected_signature },
            ignored_count: results.count { |result| result[:status] == :ignored_unsupported },
            trigger_event_ids: results.filter_map { |result| result[:trigger_event_id] }
          }.merge(status: results.empty? || results.any? { |result| result[:status] != :rejected_signature } ? :accepted : :unauthorized)
        end

        def process_workflow(workflow:, provider:, source:, raw_body:, payload:, event_type:, delivery_id:, ignored:, reason:)
          verification = WebhookSignatureVerifier.verify(
            provider: provider,
            raw_body: raw_body,
            signature: request.headers["Linear-Signature"],
            secret: workflow.tracker_connection.resolved_tracker_setting("webhook_secret"),
            payload: payload
          )
          return rejected_signature_result(workflow, source, provider, delivery_id, payload, event_type, verification) unless verification[:ok]
          return ignored_event_result(workflow, source, provider, delivery_id, payload, event_type, reason) if ignored

          enqueue_result = WorkflowTriggerScheduler.enqueue(
            workflow_id: workflow.id,
            source: source,
            provider: provider,
            delivery_id: delivery_id,
            signature_state: "verified",
            metadata: webhook_metadata(payload, event_type: event_type)
          )

          { status: enqueue_result[:queued] ? :queued : :coalesced, trigger_event_id: enqueue_result[:trigger_event_id] }
        end

        def rejected_signature_result(workflow, source, provider, delivery_id, payload, event_type, verification)
          event = WorkflowTriggerEvent.create!(
            managed_workflow: workflow,
            source: source,
            provider: provider,
            delivery_id: delivery_id,
            status: "rejected_signature",
            signature_state: verification[:signature_state],
            requested_at: Time.current,
            error: verification[:error],
            metadata: webhook_metadata(payload, event_type: event_type)
          )
          OrchestratorState.record_trigger!(
            workflow_id: workflow.id,
            source: source,
            requested_at: event.requested_at,
            trigger_event: event
          )

          { status: :rejected_signature, trigger_event_id: event.id }
        end

        def ignored_event_result(workflow, source, provider, delivery_id, payload, event_type, reason)
          event = WorkflowTriggerEvent.create!(
            managed_workflow: workflow,
            source: source,
            provider: provider,
            delivery_id: delivery_id,
            status: "ignored_unsupported",
            signature_state: "verified",
            requested_at: Time.current,
            error: reason,
            metadata: webhook_metadata(payload, event_type: event_type)
          )
          OrchestratorState.record_trigger!(
            workflow_id: workflow.id,
            source: source,
            requested_at: event.requested_at,
            trigger_event: event
          )

          { status: :ignored_unsupported, trigger_event_id: event.id }
        end

        def webhook_metadata(payload, event_type:)
          {
            event_type: event_type,
            action: payload["action"],
            resource_type: payload["type"],
            project_slug: payload.dig("data", "project", "slugId"),
            webhook_id: payload["webhookId"]
          }.compact
        end

        def parse_payload(raw_body)
          JSON.parse(raw_body)
        rescue JSON::ParserError
          {}
        end

        def render_result(result)
          render json: result.except(:status), status: result[:status] == :accepted ? 202 : 401
        end
    end
  end
end
