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

        render json: {
          issue_identifier: identifier,
          issue_id: running&.dig(:issue_id) || retrying&.dig(:issue_id),
          status: running ? "running" : "retrying",
          workspace: { path: Symphony.workspace&.workspace_path(identifier) },
          attempts: {
            restart_count: [ (retrying&.dig(:attempt) || 0) - 1, 0 ].max,
            current_retry_attempt: retrying&.dig(:attempt) || 0
          },
          running: running,
          retry: retrying,
          logs: { codex_session_logs: [] },
          recent_events: [],
          last_error: retrying&.dig(:error),
          tracked: {}
        }
      end
    end
  end
end
