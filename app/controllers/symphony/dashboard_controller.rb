module Symphony
  class DashboardController < ApplicationController
    def show
      @snapshot = ::Symphony.orchestrator&.snapshot || empty_snapshot
      @console_snapshot = ::Symphony::ConsoleSnapshot.build
    end

    private

      def empty_snapshot
        {
          generated_at: Time.now.utc.iso8601,
          counts: { running: 0, retrying: 0 },
          running: [],
          retrying: [],
          codex_totals: { input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0 },
          rate_limits: nil
        }
      end
  end
end
