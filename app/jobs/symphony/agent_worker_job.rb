module Symphony
  class AgentWorkerJob < ApplicationJob
    queue_as :symphony_agents

    def perform(issue_id:, issue_identifier:, issue_title:, issue_state:, attempt: nil)
      issue = Issue.new(id: issue_id, identifier: issue_identifier, title: issue_title, state: issue_state)

      runner = AgentRunner.new(
        tracker: Symphony.tracker,
        workspace: Symphony.workspace,
        agent: Symphony.agent,
        config: Symphony.config,
        prompt_template: Symphony.workflow_store.prompt_template,
        on_event: ->(event) { Symphony.orchestrator&.handle_codex_update(issue_id, event) }
      )

      result = runner.run(issue: issue, attempt: attempt)

      if result[:ok]
        Symphony.orchestrator&.on_worker_exit_normal(issue_id, issue_identifier)
      else
        Symphony.orchestrator&.on_worker_exit_abnormal(
          issue_id, issue_identifier,
          attempt: (attempt || 0) + 1,
          error: result[:error].to_s
        )
      end
    end
  end
end
