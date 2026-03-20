module Symphony
  class WorkflowConfigBuilder
    def self.build(managed_workflow)
      new(managed_workflow).build
    end

    def initialize(managed_workflow)
      @managed_workflow = managed_workflow
    end

    def build
      config = {
        "tracker" => { "kind" => @managed_workflow.tracker_connection.kind },
        "agent" => { "kind" => @managed_workflow.agent_connection.kind }
      }

      config.deep_merge!(tracker_config)
      config.deep_merge!(agent_config)
      config.deep_merge!(runtime_config)
      config
    end

    private
      def tracker_config
        section = stringify_hash(@managed_workflow.tracker_connection.config)
        section = section["tracker"] if section.key?("tracker")

        { "tracker" => section || {} }
      end

      def agent_config
        stringify_hash(@managed_workflow.agent_connection.config)
      end

      def runtime_config
        stringify_hash(@managed_workflow.runtime_config)
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
