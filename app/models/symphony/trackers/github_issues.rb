require "time"

module Symphony
  module Trackers
    class GithubIssues < Base
      PAGE_SIZE = 100
      MAX_PAGES = 10

      def initialize(api_key:, repo:, endpoint:, active_states: [])
        @api_key = api_key
        @repo = repo
        @endpoint = endpoint
        @active_states = active_states
        build_connection
      end

      def reconfigure(api_key:, repo:, endpoint:, active_states: @active_states)
        endpoint_changed = @endpoint != endpoint
        @api_key = api_key
        @repo = repo
        @endpoint = endpoint
        @active_states = active_states
        build_connection if endpoint_changed
        :ok
      end

      def fetch_candidate_issues(active_states:)
        fetch_issues_by_states(active_states)
      end

      def fetch_issue_states_by_ids(ids)
        normalized_ids = ids.map(&:to_s)
        return { ok: true, issues: [] } if normalized_ids.empty?

        result = list_issues(state: "all")
        return result if result[:error]

        issues = result[:issues]
          .select { |issue| normalized_ids.include?(issue["node_id"].to_s) }
          .map { |issue| normalize_issue(issue, active_states: @active_states) }

        { ok: true, issues: issues }
      end

      def fetch_issues_by_states(states)
        normalized_states = states.map(&:to_s).reject(&:blank?)
        return { ok: true, issues: [] } if normalized_states.empty?

        issues_by_id = {}

        normalized_states.each do |state|
          result = list_issues(state: "open", label: state)
          return result if result[:error]

          result[:issues].each do |issue|
            issues_by_id[issue["node_id"].to_s] ||= normalize_issue(issue, active_states: normalized_states)
          end
        end

        { ok: true, issues: issues_by_id.values }
      end

      private
        def build_connection
          @conn = Faraday.new(url: @endpoint) do |f|
            f.response :json
            f.options.timeout = 30
          end
        end

        def list_issues(state:, label: nil)
          page = 1
          issues = []

          loop do
            response = @conn.get(repo_issues_path) do |req|
              req.headers["Authorization"] = "token #{@api_key}"
              req.headers["Accept"] = "application/vnd.github+json"
              req.params["state"] = state
              req.params["per_page"] = PAGE_SIZE
              req.params["page"] = page
              req.params["labels"] = label if label.present?
            end

            unless response.status == 200
              Rails.logger.error("[Symphony::Trackers::GithubIssues] API error status=#{response.status}")
              return { error: :github_api_status, status: response.status }
            end

            issues.concat(Array(response.body))

            link_header = response.headers["link"].to_s
            break unless link_header.include?('rel="next"')

            page += 1
            break if page > MAX_PAGES
          end

          { ok: true, issues: issues }
        rescue Faraday::Error => e
          Rails.logger.error("[Symphony::Trackers::GithubIssues] Request failed: #{e.message}")
          { error: :github_transport_error, message: e.message }
        end

        def repo_issues_path
          "repos/#{@repo}/issues"
        end

        def normalize_issue(issue, active_states:)
          labels = extract_labels(issue)
          identifier = "#{@repo}##{issue["number"]}"

          Symphony::Issue.new(
            id: issue["node_id"],
            identifier: identifier,
            title: issue["title"],
            description: issue["body"],
            priority: extract_priority(labels),
            state: infer_state(issue, labels, active_states),
            branch_name: identifier.parameterize(separator: "-"),
            url: issue["html_url"],
            labels: labels,
            blocked_by: [],
            created_at: parse_time(issue["created_at"]),
            updated_at: parse_time(issue["updated_at"])
          )
        end

        def extract_labels(issue)
          Array(issue["labels"]).filter_map { |label| label["name"]&.downcase }
        end

        def extract_priority(labels)
          labels.each do |label|
            match = /\Apriority:(\d+)\z/i.match(label)
            return match[1].to_i if match
          end

          nil
        end

        def infer_state(issue, labels, active_states)
          match = Array(active_states).find do |state|
            labels.include?(state.to_s.downcase)
          end
          return match if match

          return "Closed" if issue["state"].to_s == "closed"

          Array(active_states).first || issue["state"].to_s.titleize
        end

        def parse_time(value)
          return nil if value.blank?

          Time.iso8601(value)
        rescue ArgumentError
          nil
        end
    end
  end
end
