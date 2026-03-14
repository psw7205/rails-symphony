module Symphony
  module Agents
    class Base
      def start_session(workspace_path:, config:)
        raise NotImplementedError
      end

      # yields events via block: { event:, timestamp:, payload: }
      def run_turn(session:, prompt:, issue:, &on_message)
        raise NotImplementedError
      end

      def stop_session(session)
        raise NotImplementedError
      end
    end
  end
end
