module Symphony
  module Trackers
    class Base
      def capabilities
        [ :read_issues, :read_issue_states, :refresh ]
      end

      def fetch_candidate_issues(active_states:)
        raise NotImplementedError
      end

      def fetch_issue_states_by_ids(ids)
        raise NotImplementedError
      end

      def fetch_issues_by_states(states)
        raise NotImplementedError
      end
    end
  end
end
