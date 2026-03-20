module Symphony
  class AgentWorkerJob < ApplicationJob
    queue_as :symphony_agents

    def perform(issue_id:, issue_identifier:, issue_title:, issue_state:, attempt: nil, managed_workflow_id: nil)
      context = runtime_context_for(managed_workflow_id)
      issue = restore_issue(issue_id, issue_identifier, issue_title, issue_state, managed_workflow_id)

      runner = AgentRunner.new(
        tracker: context[:tracker],
        workspace: context[:workspace],
        agent: context[:agent],
        config: context[:config],
        prompt_template: context[:prompt_template],
        on_event: ->(event) { context[:orchestrator]&.handle_codex_update(issue_id, event) }
      )

      result = runner.run(issue: issue, attempt: attempt)

      if result[:ok]
        context[:orchestrator]&.on_worker_exit_normal(issue_id, issue_identifier)
      else
        context[:orchestrator]&.on_worker_exit_abnormal(
          issue_id, issue_identifier,
          attempt: (attempt || 0) + 1,
          error: result[:error].to_s
        )
      end
    end

    private

      def restore_issue(issue_id, issue_identifier, issue_title, issue_state, managed_workflow_id = nil)
        persisted_issue_id = if managed_workflow_id.present?
          "#{managed_workflow_id}:#{issue_id}"
        else
          issue_id
        end

        pi = PersistedIssue.find_by(id: persisted_issue_id)
        if pi
          Issue.new(
            id: pi.source_issue_id.presence || issue_id, identifier: pi.identifier, title: pi.title,
            description: pi.description, priority: pi.priority, state: pi.state,
            branch_name: pi.branch_name, url: pi.url,
            labels: pi.labels || [], blocked_by: pi.blocked_by || [],
            created_at: pi.created_at, updated_at: pi.updated_at
          )
        else
          Issue.new(id: issue_id, identifier: issue_identifier, title: issue_title, state: issue_state)
        end
      end

      def runtime_context_for(managed_workflow_id)
        if managed_workflow_id.present?
          runtime_context = Symphony::WorkflowRuntimeManager.fetch(managed_workflow_id)
          {
            tracker: runtime_context.tracker,
            workspace: runtime_context.workspace,
            agent: runtime_context.agent,
            config: runtime_context.workflow_store.service_config,
            prompt_template: runtime_context.workflow_store.prompt_template,
            orchestrator: runtime_context.orchestrator
          }
        else
          {
            tracker: Symphony.tracker,
            workspace: Symphony.workspace,
            agent: Symphony.agent,
            config: Symphony.config,
            prompt_template: Symphony.workflow_store.prompt_template,
            orchestrator: Symphony.orchestrator
          }
        end
      end
  end
end
