require "test_helper"
require "tempfile"

class Symphony::WorkflowTest < ActiveSupport::TestCase
  test "parses YAML front matter and prompt body" do
    content = "---\ntracker:\n  kind: linear\n---\nYou are working on {{ issue.identifier }}"
    result = Symphony::Workflow.parse(content)
    assert_equal "linear", result[:config].dig("tracker", "kind")
    assert_equal "You are working on {{ issue.identifier }}", result[:prompt_template]
  end

  test "returns empty config when no front matter" do
    content = "Just a prompt"
    result = Symphony::Workflow.parse(content)
    assert_equal({}, result[:config])
    assert_equal "Just a prompt", result[:prompt_template]
  end

  test "errors on non-map front matter" do
    content = "---\n- item1\n- item2\n---\nprompt"
    result = Symphony::Workflow.parse(content)
    assert_equal :workflow_front_matter_not_a_map, result[:error]
  end

  test "loads from file path" do
    file = Tempfile.new(["workflow", ".md"])
    file.write("---\ntracker:\n  kind: linear\n---\nHello {{ issue.title }}")
    file.close
    result = Symphony::Workflow.load(file.path)
    assert_equal "linear", result[:config].dig("tracker", "kind")
    assert_includes result[:prompt_template], "Hello"
  ensure
    file&.unlink
  end

  test "returns error for missing file" do
    result = Symphony::Workflow.load("/nonexistent/WORKFLOW.md")
    assert_equal :missing_workflow_file, result[:error]
  end

  test "trims prompt body" do
    content = "---\ntracker:\n  kind: linear\n---\n\n  Hello  \n\n"
    result = Symphony::Workflow.parse(content)
    assert_equal "Hello", result[:prompt_template]
  end
end
