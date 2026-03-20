require "yaml"

module Symphony
  # File-backed WORKFLOW.md parser kept for legacy mode. This is intentionally
  # distinct from the DB-backed Symphony::ManagedWorkflow model.
  class Workflow
    def self.load(path)
      unless File.exist?(path)
        return { error: :missing_workflow_file }
      end
      content = File.read(path)
      parse(content)
    rescue => e
      { error: :workflow_parse_error, message: e.message }
    end

    def self.parse(content)
      if content.start_with?("---")
        parts = content.split(/^---\s*$/, 3)
        yaml_str = parts[1] || ""
        body = parts[2] || ""

        config = YAML.safe_load(yaml_str, permitted_classes: [ Symbol ]) || {}
        unless config.is_a?(Hash)
          return { error: :workflow_front_matter_not_a_map }
        end

        { config: config, prompt_template: body.strip }
      else
        { config: {}, prompt_template: content.strip }
      end
    rescue Psych::SyntaxError => e
      { error: :workflow_parse_error, message: e.message }
    end
  end
end
