module Symphony
  module Trackers
    class Linear < Base
      ISSUE_PAGE_SIZE = 50

      POLL_QUERY = <<~GRAPHQL
        query SymphonyLinearPoll($projectSlug: String!, $stateNames: [String!]!, $first: Int!, $relationFirst: Int!, $after: String) {
          issues(filter: {project: {slugId: {eq: $projectSlug}}, state: {name: {in: $stateNames}}}, first: $first, after: $after) {
            nodes {
              id
              identifier
              title
              description
              priority
              state { name }
              branchName
              url
              labels { nodes { name } }
              inverseRelations(first: $relationFirst) {
                nodes {
                  type
                  issue { id identifier state { name } }
                }
              }
              createdAt
              updatedAt
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      GRAPHQL

      IDS_QUERY = <<~GRAPHQL
        query SymphonyLinearIssuesById($ids: [ID!]!, $first: Int!, $relationFirst: Int!) {
          issues(filter: {id: {in: $ids}}, first: $first) {
            nodes {
              id
              identifier
              title
              description
              priority
              state { name }
              branchName
              url
              labels { nodes { name } }
              inverseRelations(first: $relationFirst) {
                nodes {
                  type
                  issue { id identifier state { name } }
                }
              }
              createdAt
              updatedAt
            }
          }
        }
      GRAPHQL

      def initialize(api_key:, endpoint:, project_slug:)
        @api_key = api_key
        @endpoint = endpoint
        @project_slug = project_slug
        build_connection
      end

      def reconfigure(api_key:, endpoint:, project_slug:)
        endpoint_changed = @endpoint != endpoint
        @api_key = api_key
        @endpoint = endpoint
        @project_slug = project_slug
        build_connection if endpoint_changed
        :ok
      end

      def fetch_candidate_issues(active_states:)
        fetch_paginated(active_states)
      end

      def fetch_issue_states_by_ids(ids)
        return { ok: true, issues: [] } if ids.empty?

        result = graphql(IDS_QUERY, {
          ids: ids.uniq,
          first: [ ids.length, ISSUE_PAGE_SIZE ].min,
          relationFirst: ISSUE_PAGE_SIZE
        })
        return result if result[:error]

        decode_response(result[:data])
      end

      def fetch_issues_by_states(states)
        return { ok: true, issues: [] } if states.empty?
        fetch_paginated(states)
      end

      private

        def build_connection
          @conn = Faraday.new(url: @endpoint) do |f|
          f.request :json
          f.response :json
          f.options.timeout = 30
          end
        end

        def fetch_paginated(state_names, after_cursor = nil, acc = [])
          result = graphql(POLL_QUERY, {
            projectSlug: @project_slug,
            stateNames: state_names,
            first: ISSUE_PAGE_SIZE,
            relationFirst: ISSUE_PAGE_SIZE,
            after: after_cursor
          })
          return result if result[:error]

          data = result[:data]
          issues_data = data.dig("data", "issues")
          return { error: :linear_unknown_payload } unless issues_data

          nodes = issues_data["nodes"] || []
          page_issues = nodes.filter_map { |node| normalize_issue(node) }
          all_issues = acc + page_issues

          page_info = issues_data["pageInfo"] || {}
          if page_info["hasNextPage"] && page_info["endCursor"].nil?
            { error: :linear_missing_end_cursor }
          elsif page_info["hasNextPage"]
            fetch_paginated(state_names, page_info["endCursor"], all_issues)
          else
            { ok: true, issues: all_issues }
          end
        end

        def graphql(query, variables)
          response = @conn.post do |req|
            req.headers["Authorization"] = @api_key
            req.body = { query: query, variables: variables }
          end

          unless response.status == 200
            Rails.logger.error("[Symphony::Trackers::Linear] API error status=#{response.status}")
            return { error: :linear_api_status, status: response.status }
          end

          body = response.body
          if body["errors"]
            Rails.logger.error("[Symphony::Trackers::Linear] GraphQL errors: #{body["errors"]}")
            return { error: :linear_graphql_errors, details: body["errors"] }
          end

          { ok: true, data: body }
        rescue Faraday::Error => e
          Rails.logger.error("[Symphony::Trackers::Linear] Request failed: #{e.message}")
          { error: :linear_transport_error, message: e.message }
        end

        def decode_response(body)
          nodes = body.dig("data", "issues", "nodes")
          return { error: :linear_unknown_payload } unless nodes

          issues = nodes.filter_map { |node| normalize_issue(node) }
          { ok: true, issues: issues }
        end

        def normalize_issue(node)
          return nil unless node.is_a?(Hash)

          Issue.new(
            id: node["id"],
            identifier: node["identifier"],
            title: node["title"],
            description: node["description"],
            priority: node["priority"]&.is_a?(Integer) ? node["priority"] : nil,
            state: node.dig("state", "name"),
            branch_name: node["branchName"],
            url: node["url"],
            labels: extract_labels(node),
            blocked_by: extract_blockers(node),
            created_at: parse_datetime(node["createdAt"]),
            updated_at: parse_datetime(node["updatedAt"])
          )
        end

        def extract_labels(node)
          labels = node.dig("labels", "nodes")
          return [] unless labels.is_a?(Array)
          labels.filter_map { |l| l["name"]&.downcase }
        end

        def extract_blockers(node)
          relations = node.dig("inverseRelations", "nodes")
          return [] unless relations.is_a?(Array)

          relations.filter_map do |rel|
            next unless rel["type"].to_s.strip.downcase == "blocks"
            blocker = rel["issue"]
            next unless blocker.is_a?(Hash)

            {
              "id" => blocker["id"],
              "identifier" => blocker["identifier"],
              "state" => blocker.dig("state", "name")
            }
          end
        end

        def parse_datetime(raw)
          return nil if raw.nil?
          Time.iso8601(raw)
        rescue ArgumentError
          nil
        end
    end
  end
end
