module Api
  module V1
    class IssuesController < ApplicationController
      skip_forgery_protection

      def show
        unless Symphony.orchestrator
          return render json: { error: { code: "orchestrator_unavailable", message: "Orchestrator is not running" } }, status: 503
        end

        snapshot = Symphony.orchestrator.snapshot
        identifier = params[:issue_identifier]

        running = snapshot[:running].find { |r| r[:issue_identifier] == identifier }
        retrying = snapshot[:retrying].find { |r| r[:issue_identifier] == identifier }

        unless running || retrying
          return render json: { error: { code: "issue_not_found", message: "Issue not found" } }, status: 404
        end

        render_issue_json(
          identifier: identifier,
          issue_id: running&.dig(:issue_id) || retrying&.dig(:issue_id),
          running: running,
          retrying: retrying,
          workspace_path: Symphony.workspace&.workspace_path(identifier),
          orchestrator_state: Symphony::OrchestratorState.current,
          trigger_events: Symphony::WorkflowTriggerEvent.none
        )
      end

      def show_workflow
        context = Symphony::WorkflowRuntimeManager.fetch(params[:workflow_id])
        snapshot = context.orchestrator.snapshot
        identifier = params[:issue_identifier]

        running = snapshot[:running].find { |r| r[:issue_identifier] == identifier }
        retrying = snapshot[:retrying].find { |r| r[:issue_identifier] == identifier }

        unless running || retrying
          return render json: { error: { code: "issue_not_found", message: "Issue not found" } }, status: 404
        end

        render_issue_json(
          identifier: identifier,
          issue_id: running&.dig(:issue_id) || retrying&.dig(:issue_id),
          running: running,
          retrying: retrying,
          workspace_path: context.workspace.workspace_path(identifier),
          orchestrator_state: Symphony::OrchestratorState.find_by(managed_workflow_id: params[:workflow_id]),
          trigger_events: Symphony::WorkflowTriggerEvent.where(managed_workflow_id: params[:workflow_id]).order(requested_at: :desc).limit(5)
        )
      end

      private
        def render_issue_json(identifier:, issue_id:, running:, retrying:, workspace_path:, orchestrator_state:, trigger_events:)
          render json: {
            issue_identifier: identifier,
            issue_id: issue_id,
            status: running ? "running" : "retrying",
            workspace: { path: workspace_path },
            attempts: {
              restart_count: [ (retrying&.dig(:attempt) || 0) - 1, 0 ].max,
              current_retry_attempt: retrying&.dig(:attempt) || 0
            },
            running: running,
            retry: retrying,
            logs: { codex_session_logs: [] },
            recent_events: trigger_events.map do |event|
              {
                source: event.source,
                status: event.status,
                requested_at: event.requested_at&.iso8601,
                error: event.error
              }
            end,
            last_error: retrying&.dig(:error) || orchestrator_state&.last_tick_error,
            tracked: {
              last_trigger_source: orchestrator_state&.last_trigger_source,
              last_triggered_at: orchestrator_state&.last_triggered_at&.iso8601,
              last_tick_status: orchestrator_state&.last_tick_status,
              last_tick_error: orchestrator_state&.last_tick_error
            }
          }
        end
    end
  end
end
