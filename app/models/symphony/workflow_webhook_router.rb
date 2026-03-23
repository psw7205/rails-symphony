module Symphony
  class WorkflowWebhookRouter
    def self.route(provider:, event_type:, payload:)
      case provider.to_s
      when "github"
        route_github(event_type: event_type, payload: payload)
      when "linear"
        route_linear(event_type: event_type, payload: payload)
      else
        { workflows: [], ignored: true, reason: "unsupported_provider" }
      end
    end

    class << self
      private
        def route_github(event_type:, payload:)
          repo = payload.dig("repository", "full_name").to_s
          workflows = active_workflows_for("github").select do |workflow|
            workflow.tracker_connection.tracker_setting("repo").to_s.casecmp(repo).zero?
          end

          {
            workflows: workflows,
            ignored: repo.blank? || !supported_github_event?(event_type),
            reason: repo.blank? ? "missing_repository" : "unsupported_event"
          }
        end

        def route_linear(event_type:, payload:)
          project_slug = payload.dig("data", "project", "slugId").presence || payload.dig("data", "projectSlug").presence
          project_id = payload.dig("data", "project", "id").presence || payload.dig("data", "projectId").presence
          workflows = active_workflows_for("linear").select do |workflow|
            matches_linear_project?(workflow.tracker_connection, project_slug, project_id)
          end

          {
            workflows: workflows,
            ignored: payload["type"].to_s != "Issue" || event_type.to_s != "Issue" || payload["action"].blank?,
            reason: "unsupported_event"
          }
        end

        def matches_linear_project?(tracker_connection, project_slug, project_id)
          configured_project_slug = tracker_connection.tracker_setting("project_slug").to_s
          configured_project_id = tracker_connection.tracker_setting("project_id").to_s

          return true if configured_project_slug.present? && configured_project_slug == project_slug.to_s
          return true if configured_project_id.present? && configured_project_id == project_id.to_s

          false
        end

        def supported_github_event?(event_type)
          event_type.to_s.casecmp("issues").zero?
        end

        def active_workflows_for(kind)
          ManagedWorkflow.includes(:tracker_connection)
            .joins(:tracker_connection)
            .where(status: "active", symphony_tracker_connections: { kind: kind })
            .order(:id)
        end
    end
  end
end
