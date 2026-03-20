module Symphony
  class Orchestrator
    module Persistable
      def persist_dispatch(issue, attempt)
        persisted_issue_id = persisted_issue_id_for(issue.id)
        persisted_issue_attributes = {
          identifier: issue.identifier,
          title: issue.title,
          description: issue.description,
          priority: issue.priority,
          state: issue.state,
          branch_name: issue.branch_name,
          url: issue.url,
          labels: issue.respond_to?(:labels) ? issue.labels : [],
          blocked_by: issue.respond_to?(:blocked_by) ? issue.blocked_by : []
        }
        if managed_workflow_id.present?
          persisted_issue_attributes[:managed_workflow_id] = managed_workflow_id
          persisted_issue_attributes[:source_issue_id] = issue.id
          persisted_issue_attributes[:tracker_kind] = config.tracker_kind
        end

        pi = PersistedIssue.find_or_initialize_by(id: persisted_issue_id)
        pi.update!(persisted_issue_attributes)

        RunAttempt.create!(
          issue_id: persisted_issue_id,
          managed_workflow_id: managed_workflow_id,
          attempt: attempt || 1,
          status: "running",
          started_at: Time.current
        )
      rescue => e
        Rails.logger.warn("[Orchestrator::Persistable] persist_dispatch failed: #{e.message}")
      end

      def persist_worker_exit(issue_id, status:, error: nil)
        persisted_issue_id = persisted_issue_id_for(issue_id)
        ra = scoped_run_attempts.where(issue_id: persisted_issue_id, status: "running").order(attempt: :desc).first
        ra&.update!(status: status, error: error, finished_at: Time.current)
      rescue => e
        Rails.logger.warn("[Orchestrator::Persistable] persist_worker_exit failed: #{e.message}")
      end

      def persist_retry(issue_id, identifier, attempt:, due_at:, error: nil)
        persisted_issue_id = persisted_issue_id_for(issue_id)
        RetryEntry.upsert(
          { issue_id: persisted_issue_id, managed_workflow_id: managed_workflow_id,
            identifier: identifier, attempt: attempt,
            due_at: due_at, error: error,
            created_at: Time.current, updated_at: Time.current },
          unique_by: :issue_id
        )
      rescue => e
        Rails.logger.warn("[Orchestrator::Persistable] persist_retry failed: #{e.message}")
      end

      def clear_persisted_retry(issue_id)
        scoped_retry_entries.where(issue_id: persisted_issue_id_for(issue_id)).delete_all
      rescue => e
        Rails.logger.warn("[Orchestrator::Persistable] clear_persisted_retry failed: #{e.message}")
      end

      def persist_codex_totals
        state = current_orchestrator_state
        state.update!(
          codex_total_input_tokens: @codex_totals[:input_tokens],
          codex_total_output_tokens: @codex_totals[:output_tokens],
          codex_total_tokens: @codex_totals[:total_tokens],
          codex_total_seconds_running: @codex_totals[:seconds_running]
        )
      rescue => e
        Rails.logger.warn("[Orchestrator::Persistable] persist_codex_totals failed: #{e.message}")
      end

      def restore_from_db!
        # Restore codex totals
        state = stored_orchestrator_state
        if state
          @codex_totals[:input_tokens] = state.codex_total_input_tokens || 0
          @codex_totals[:output_tokens] = state.codex_total_output_tokens || 0
          @codex_totals[:total_tokens] = state.codex_total_tokens || 0
          @codex_totals[:seconds_running] = state.codex_total_seconds_running || 0.0
          @codex_rate_limits = state.codex_rate_limits
          Rails.logger.info("[Orchestrator] Restored codex totals from DB")
        end

        # Restore retry entries
        RetryEntry.find_each do |entry|
          @retry_attempts[entry.issue_id] = {
            identifier: entry.identifier,
            attempt: entry.attempt,
            delay_ms: 0,
            due_at: entry.due_at,
            error: entry.error
          }
          @claimed.add(entry.issue_id)
        end
        Rails.logger.info("[Orchestrator] Restored #{@retry_attempts.size} retry entries from DB")

        # Mark incomplete run attempts as interrupted
        RunAttempt.where(status: "running").update_all(status: "interrupted", finished_at: Time.current)
      rescue => e
        Rails.logger.warn("[Orchestrator::Persistable] restore_from_db! failed: #{e.message}")
      end

      def current_orchestrator_state
        return OrchestratorState.current if managed_workflow_id.blank?

        OrchestratorState.for_workflow!(managed_workflow_id)
      end

      def stored_orchestrator_state
        return OrchestratorState.first if managed_workflow_id.blank?

        OrchestratorState.find_by(managed_workflow_id: managed_workflow_id)
      end

      def persisted_issue_id_for(source_issue_id)
        return source_issue_id if managed_workflow_id.blank?

        "#{managed_workflow_id}:#{source_issue_id}"
      end

      def scoped_retry_entries
        return RetryEntry.all if managed_workflow_id.blank?

        RetryEntry.where(managed_workflow_id: managed_workflow_id)
      end

      def scoped_run_attempts
        return RunAttempt.all if managed_workflow_id.blank?

        RunAttempt.where(managed_workflow_id: managed_workflow_id)
      end
    end
  end
end
