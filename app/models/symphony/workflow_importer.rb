module Symphony
  class WorkflowImporter
    def self.import!(workflow_path:, project_name: nil, workflow_name: nil)
      new(
        workflow_path: workflow_path,
        project_name: project_name,
        workflow_name: workflow_name
      ).import!
    end

    def initialize(workflow_path:, project_name:, workflow_name:)
      @workflow_path = workflow_path.to_s
      @project_name = project_name.presence
      @workflow_name = workflow_name.presence
    end

    def import!
      raise ArgumentError, "workflow_path is required" if @workflow_path.blank?

      result = Workflow.load(@workflow_path)
      raise ArgumentError, import_error_message(result) if result[:error]

      config = stringify_hash(result[:config])
      workflow_name = resolved_workflow_name
      project = ManagedProject.create!(
        name: resolved_project_name,
        slug: resolved_project_name.parameterize,
        status: "active"
      )
      tracker_connection = TrackerConnection.create!(
        name: "#{workflow_name} Tracker",
        kind: tracker_kind(config),
        status: "active",
        config: tracker_config(config)
      )
      agent_connection = AgentConnection.create!(
        name: "#{workflow_name} Agent",
        kind: agent_kind(config),
        status: "active",
        config: agent_config(config)
      )

      ManagedWorkflow.create!(
        managed_project: project,
        tracker_connection: tracker_connection,
        agent_connection: agent_connection,
        name: workflow_name,
        slug: workflow_name.parameterize,
        status: "active",
        prompt_template: result[:prompt_template].to_s,
        runtime_config: runtime_config(config)
      )
    end

    private
      def resolved_project_name
        @project_name || derived_name
      end

      def resolved_workflow_name
        @workflow_name || derived_name
      end

      def derived_name
        File.basename(File.dirname(@workflow_path)).tr("_-", " ").squeeze(" ").strip.titleize
      end

      def tracker_kind(config)
        config.dig("tracker", "kind") || "memory"
      end

      def agent_kind(config)
        config.dig("agent", "kind") || "codex"
      end

      def tracker_config(config)
        config.fetch("tracker", {}).except("kind")
      end

      def agent_config(config)
        {}.tap do |result|
          agent_section = config.fetch("agent", {}).except("kind")
          result["agent"] = agent_section if agent_section.present?
          result["codex"] = config["codex"] if config["codex"].present?
        end
      end

      def runtime_config(config)
        config.except("tracker", "agent", "codex")
      end

      def import_error_message(result)
        result[:message].presence || result[:error].to_s
      end

      def stringify_hash(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            result[key.to_s] = stringify_hash(nested_value)
          end
        when Array
          value.map { |nested_value| stringify_hash(nested_value) }
        else
          value
        end
      end
  end
end
