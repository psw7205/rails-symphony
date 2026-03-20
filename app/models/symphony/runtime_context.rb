module Symphony
  class RuntimeContext
    attr_reader :managed_workflow, :tracker, :workspace, :agent, :workflow_store, :orchestrator

    def initialize(managed_workflow:, tracker:, workspace:, agent:, workflow_store:, orchestrator:)
      @managed_workflow = managed_workflow
      @tracker = tracker
      @workspace = workspace
      @agent = agent
      @workflow_store = workflow_store
      @orchestrator = orchestrator
    end
  end
end
