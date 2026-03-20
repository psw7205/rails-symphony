module Symphony
  class WorkflowRuntimeFactory
    def self.build(managed_workflow_id)
      managed_workflow = ManagedWorkflow.includes(:tracker_connection, :agent_connection).find(managed_workflow_id)
      workflow_store = ManagedWorkflowStore.new(managed_workflow.id)
      config = workflow_store.service_config
      workspace = Workspace.new(
        root: config.workspace_root,
        hooks: config.hooks,
        hooks_timeout_ms: config.hooks_timeout_ms
      )
      tracker = build_tracker(config)
      agent = Agents::Codex.new(config: config)
      orchestrator = Orchestrator.new(
        tracker: tracker,
        workspace: workspace,
        agent: agent,
        workflow_store: workflow_store,
        managed_workflow_id: managed_workflow.id
      )

      RuntimeContext.new(
        managed_workflow: managed_workflow,
        tracker: tracker,
        workspace: workspace,
        agent: agent,
        workflow_store: workflow_store,
        orchestrator: orchestrator
      )
    end

    def self.build_tracker(config)
      case config.tracker_kind
      when "linear"
        Trackers::Linear.new(
          api_key: config.tracker_api_key,
          endpoint: config.tracker_endpoint,
          project_slug: config.tracker_project_slug
        )
      when "memory"
        Trackers::Memory.new
      else
        raise "Unsupported tracker kind: #{config.tracker_kind}"
      end
    end
  end
end
