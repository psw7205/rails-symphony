require "test_helper"

class Symphony::PromptBuilderTest < ActiveSupport::TestCase
  test "renders issue fields into template" do
    template = "Working on {{ issue.identifier }}: {{ issue.title }}"
    issue = Symphony::Issue.new(id: "1", identifier: "MT-42", title: "Fix bug", state: "Todo")
    result = Symphony::PromptBuilder.render(template, issue: issue)
    assert_equal "Working on MT-42: Fix bug", result
  end

  test "renders attempt variable for retries" do
    template = '{% if attempt %}Retry #{{ attempt }}{% endif %}'
    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "t", state: "Todo")
    result = Symphony::PromptBuilder.render(template, issue: issue, attempt: 3)
    assert_equal "Retry #3", result
  end

  test "attempt is absent on first run" do
    template = "{% if attempt %}retry{% else %}first{% endif %}"
    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "t", state: "Todo")
    result = Symphony::PromptBuilder.render(template, issue: issue, attempt: nil)
    assert_equal "first", result
  end

  test "renders labels array" do
    template = "Labels: {{ issue.labels | join: ', ' }}"
    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "t", state: "Todo", labels: ["bug", "urgent"])
    result = Symphony::PromptBuilder.render(template, issue: issue)
    assert_equal "Labels: bug, urgent", result
  end

  test "raises on unknown variable in strict mode" do
    template = "{{ unknown_var }}"
    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "t", state: "Todo")
    assert_raises(Symphony::PromptBuilder::RenderError) do
      Symphony::PromptBuilder.render(template, issue: issue)
    end
  end

  test "uses default prompt when template is blank" do
    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "t", state: "Todo")
    result = Symphony::PromptBuilder.render("", issue: issue)
    assert_includes result, "You are working on an issue from Linear."
  end
end
