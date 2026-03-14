module Symphony
  class PollJob < ApplicationJob
    queue_as :symphony

    def perform
      Symphony.orchestrator&.tick
    end
  end
end
