require "liquid"

module Symphony
  class PromptBuilder
    class RenderError < StandardError; end

    DEFAULT_PROMPT = "You are working on an issue from Linear."

    def self.render(template_str, issue:, attempt: nil)
      if template_str.nil? || template_str.strip.empty?
        return DEFAULT_PROMPT
      end

      template = Liquid::Template.parse(template_str, error_mode: :strict)

      variables = {
        "issue" => issue_to_hash(issue),
        "attempt" => attempt
      }

      template.render!(variables, strict_variables: true, strict_filters: true)
    rescue Liquid::Error => e
      raise RenderError, "Template render failed: #{e.message}"
    end

    def self.issue_to_hash(issue)
      {
        "id" => issue.id,
        "identifier" => issue.identifier,
        "title" => issue.title,
        "description" => issue.description,
        "priority" => issue.priority,
        "state" => issue.state,
        "branch_name" => issue.branch_name,
        "url" => issue.url,
        "labels" => issue.labels,
        "blocked_by" => issue.blocked_by,
        "created_at" => issue.created_at&.iso8601,
        "updated_at" => issue.updated_at&.iso8601
      }
    end
  end
end
