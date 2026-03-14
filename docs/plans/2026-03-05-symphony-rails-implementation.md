# Symphony Rails Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rails 8 + SQLite + Solid Queue 기반 Symphony 구현 (SPEC.md Section 18.1 Core Conformance 완전 준수)

**Architecture:** WORKFLOW.md에서 config/prompt를 로드하고, Solid Queue recurring job으로 Linear을 폴링하며, issue당 격리된 workspace에서 Codex app-server를 JSON-RPC stdio 프로토콜로 구동하는 오케스트레이션 서비스. 에이전트와 트래커는 어댑터 패턴으로 교체 가능.

**Tech Stack:** Rails 8, SQLite3, Solid Queue, Liquid (template), Faraday (HTTP), Listen (file watch)

**Ref:** `symphony/SPEC.md`, `symphony/elixir/` (Elixir POC)

---

## Phase 1: Project Bootstrap

### Task 1: Rails 8 프로젝트 생성

**Files:**
- Create: Rails 프로젝트 전체 (rails new)
- Modify: `Gemfile`

**Step 1: Rails 8 앱 생성 (API mode 아닌 full, SQLite 기본)**

Run:
```bash
cd /Users/hc/Repository/rails/rails-symphony
rails new . --name=symphony --database=sqlite3 --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable --skip-hotwire --skip-jbuilder --skip-test --skip-system-test --skip-kamal --skip-thruster --skip-rubocop
```

Note: `--skip-test`는 minitest 스킵. RSpec 또는 minitest를 별도 설정.

**Step 2: Gemfile에 필수 의존성 추가**

```ruby
# Gemfile additions
gem "solid_queue"
gem "liquid"
gem "faraday"
gem "listen"

group :test do
  gem "minitest"
  gem "webmock"
  gem "mocha"
end
```

**Step 3: 의존성 설치 및 DB 설정**

Run:
```bash
bundle install
bin/rails db:create
bin/rails solid_queue:install
bin/rails db:migrate
```

**Step 4: 확인**

Run: `bin/rails runner "puts Rails.version"`
Expected: `8.x.x`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: initialize Rails 8 project with SQLite and Solid Queue"
```

---

## Phase 2: Domain Model & Configuration Layer

### Task 2: Issue 도메인 모델 (SPEC 4.1.1)

**Files:**
- Create: `app/models/symphony/issue.rb`
- Create: `test/models/symphony/issue_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/issue_test.rb
require "test_helper"

class Symphony::IssueTest < ActiveSupport::TestCase
  test "initializes with all required fields" do
    issue = Symphony::Issue.new(
      id: "abc123", identifier: "MT-42", title: "Fix bug",
      description: "Details", priority: 1, state: "Todo",
      labels: ["urgent"], blocked_by: [], url: "https://linear.app/..."
    )
    assert_equal "abc123", issue.id
    assert_equal "MT-42", issue.identifier
    assert_equal 1, issue.priority
    assert_equal ["urgent"], issue.labels
  end

  test "labels default to empty array" do
    issue = Symphony::Issue.new(id: "x", identifier: "X-1", title: "t", state: "Todo")
    assert_equal [], issue.labels
    assert_equal [], issue.blocked_by
  end

  test "has_non_terminal_blockers? returns true when blocker state is active" do
    issue = Symphony::Issue.new(
      id: "x", identifier: "X-1", title: "t", state: "Todo",
      blocked_by: [{ "id" => "b1", "identifier" => "X-2", "state" => "In Progress" }]
    )
    assert issue.has_non_terminal_blockers?(["done", "closed", "cancelled", "canceled", "duplicate"])
  end

  test "has_non_terminal_blockers? returns false when all blockers terminal" do
    issue = Symphony::Issue.new(
      id: "x", identifier: "X-1", title: "t", state: "Todo",
      blocked_by: [{ "id" => "b1", "identifier" => "X-2", "state" => "Done" }]
    )
    refute issue.has_non_terminal_blockers?(["done", "closed", "cancelled", "canceled", "duplicate"])
  end
end
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/issue_test.rb`
Expected: FAIL — `Symphony::Issue` not defined

**Step 3: 구현**

```ruby
# app/models/symphony/issue.rb
module Symphony
  class Issue
    attr_reader :id, :identifier, :title, :description, :priority, :state,
                :branch_name, :url, :labels, :blocked_by, :created_at, :updated_at

    def initialize(id:, identifier:, title:, state:, description: nil, priority: nil,
                   branch_name: nil, url: nil, labels: [], blocked_by: [], created_at: nil, updated_at: nil)
      @id = id
      @identifier = identifier
      @title = title
      @description = description
      @priority = priority
      @state = state
      @branch_name = branch_name
      @url = url
      @labels = labels
      @blocked_by = blocked_by
      @created_at = created_at
      @updated_at = updated_at
    end

    def has_non_terminal_blockers?(terminal_states)
      normalized_terminal = terminal_states.map { |s| s.to_s.strip.downcase }
      blocked_by.any? do |blocker|
        blocker_state = blocker["state"].to_s.strip.downcase
        !normalized_terminal.include?(blocker_state)
      end
    end
  end
end
```

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/issue_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/symphony/issue.rb test/models/symphony/issue_test.rb
git commit -m "feat: add Symphony::Issue domain model (SPEC 4.1.1)"
```

---

### Task 3: Workflow 로더 (SPEC 5.1–5.5)

**Files:**
- Create: `app/models/symphony/workflow.rb`
- Create: `test/models/symphony/workflow_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/workflow_test.rb
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
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/workflow_test.rb`

**Step 3: 구현**

```ruby
# app/models/symphony/workflow.rb
require "yaml"

module Symphony
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
        # parts[0] is empty (before first ---), parts[1] is YAML, parts[2] is body
        yaml_str = parts[1] || ""
        body = parts[2] || ""

        config = YAML.safe_load(yaml_str, permitted_classes: [Symbol]) || {}
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
```

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/workflow_test.rb`

**Step 5: Commit**

```bash
git add app/models/symphony/workflow.rb test/models/symphony/workflow_test.rb
git commit -m "feat: add Workflow loader with YAML front matter parsing (SPEC 5.1-5.5)"
```

---

### Task 4: ServiceConfig 타입 레이어 (SPEC 6.1–6.4)

**Files:**
- Create: `app/models/symphony/service_config.rb`
- Create: `test/models/symphony/service_config_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/service_config_test.rb
require "test_helper"

class Symphony::ServiceConfigTest < ActiveSupport::TestCase
  test "applies defaults for missing values" do
    config = Symphony::ServiceConfig.new({})
    assert_equal 30_000, config.poll_interval_ms
    assert_equal 10, config.max_concurrent_agents
    assert_equal 20, config.max_turns
    assert_equal 300_000, config.max_retry_backoff_ms
    assert_equal "codex app-server", config.codex_command
    assert_equal 3_600_000, config.codex_turn_timeout_ms
    assert_equal 5_000, config.codex_read_timeout_ms
    assert_equal 300_000, config.codex_stall_timeout_ms
    assert_equal 60_000, config.hooks_timeout_ms
  end

  test "reads tracker config" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "kind" => "linear", "project_slug" => "my-project" }
    })
    assert_equal "linear", config.tracker_kind
    assert_equal "my-project", config.tracker_project_slug
  end

  test "resolves $VAR environment variables" do
    ENV["TEST_SYMPHONY_KEY"] = "secret123"
    config = Symphony::ServiceConfig.new({
      "tracker" => { "api_key" => "$TEST_SYMPHONY_KEY" }
    })
    assert_equal "secret123", config.tracker_api_key
  ensure
    ENV.delete("TEST_SYMPHONY_KEY")
  end

  test "expands ~ in workspace root" do
    config = Symphony::ServiceConfig.new({
      "workspace" => { "root" => "~/symphony-workspaces" }
    })
    assert_equal File.expand_path("~/symphony-workspaces"), config.workspace_root
  end

  test "returns default active and terminal states" do
    config = Symphony::ServiceConfig.new({})
    assert_equal ["Todo", "In Progress"], config.active_states
    assert_equal ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"], config.terminal_states
  end

  test "parses comma-separated state strings" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "active_states" => "Todo, In Progress, Rework" }
    })
    assert_equal ["Todo", "In Progress", "Rework"], config.active_states
  end

  test "reads per-state concurrency limits" do
    config = Symphony::ServiceConfig.new({
      "agent" => { "max_concurrent_agents_by_state" => { "merging" => 2 } }
    })
    assert_equal 2, config.max_concurrent_agents_for_state("Merging")
    assert_nil config.max_concurrent_agents_for_state("Todo")
  end

  test "validate! returns ok for valid config" do
    config = Symphony::ServiceConfig.new({
      "tracker" => { "kind" => "linear", "api_key" => "tok_test", "project_slug" => "proj" }
    })
    assert_equal :ok, config.validate!
  end

  test "validate! returns error for missing tracker kind" do
    config = Symphony::ServiceConfig.new({})
    result = config.validate!
    assert_equal :validation_error, result[:error]
  end

  test "treats empty $VAR resolution as missing" do
    ENV["EMPTY_KEY"] = ""
    config = Symphony::ServiceConfig.new({
      "tracker" => { "api_key" => "$EMPTY_KEY" }
    })
    assert_nil config.tracker_api_key
  ensure
    ENV.delete("EMPTY_KEY")
  end
end
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/service_config_test.rb`

**Step 3: 구현**

```ruby
# app/models/symphony/service_config.rb
module Symphony
  class ServiceConfig
    DEFAULT_ACTIVE_STATES = ["Todo", "In Progress"].freeze
    DEFAULT_TERMINAL_STATES = ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"].freeze
    DEFAULT_LINEAR_ENDPOINT = "https://api.linear.app/graphql".freeze

    def initialize(config)
      @config = config || {}
    end

    # Tracker
    def tracker_kind = dig("tracker", "kind")
    def tracker_endpoint = dig("tracker", "endpoint") || DEFAULT_LINEAR_ENDPOINT
    def tracker_project_slug = dig("tracker", "project_slug")

    def tracker_api_key
      raw = dig("tracker", "api_key")
      resolved = resolve_env_var(raw) || ENV["LINEAR_API_KEY"]
      resolved.nil? || resolved.empty? ? nil : resolved
    end

    def active_states
      parse_state_list(dig("tracker", "active_states"), DEFAULT_ACTIVE_STATES)
    end

    def terminal_states
      parse_state_list(dig("tracker", "terminal_states"), DEFAULT_TERMINAL_STATES)
    end

    # Polling
    def poll_interval_ms = integer_value("polling", "interval_ms", 30_000)

    # Workspace
    def workspace_root
      raw = dig("workspace", "root") || File.join(Dir.tmpdir, "symphony_workspaces")
      expand_path(resolve_env_var(raw) || raw)
    end

    # Hooks
    def hooks = @config.dig("hooks") || {}
    def hooks_timeout_ms = integer_value("hooks", "timeout_ms", 60_000).then { |v| v > 0 ? v : 60_000 }

    # Agent
    def max_concurrent_agents = integer_value("agent", "max_concurrent_agents", 10)
    def max_turns = integer_value("agent", "max_turns", 20)
    def max_retry_backoff_ms = integer_value("agent", "max_retry_backoff_ms", 300_000)

    def max_concurrent_agents_by_state
      raw = @config.dig("agent", "max_concurrent_agents_by_state") || {}
      raw.each_with_object({}) do |(state, limit), hash|
        int_limit = limit.to_i
        hash[state.to_s.strip.downcase] = int_limit if int_limit > 0
      end
    end

    def max_concurrent_agents_for_state(state_name)
      max_concurrent_agents_by_state[state_name.to_s.strip.downcase]
    end

    # Codex
    def codex_command = dig("codex", "command") || "codex app-server"
    def codex_turn_timeout_ms = integer_value("codex", "turn_timeout_ms", 3_600_000)
    def codex_read_timeout_ms = integer_value("codex", "read_timeout_ms", 5_000)
    def codex_stall_timeout_ms = integer_value("codex", "stall_timeout_ms", 300_000)
    def codex_approval_policy = dig("codex", "approval_policy")
    def codex_thread_sandbox = dig("codex", "thread_sandbox")
    def codex_turn_sandbox_policy = dig("codex", "turn_sandbox_policy")

    # Validation (SPEC 6.3)
    def validate!
      errors = []
      errors << "tracker.kind is required" unless tracker_kind
      errors << "tracker.kind '#{tracker_kind}' is not supported" if tracker_kind && tracker_kind != "linear"
      errors << "tracker.api_key is required" unless tracker_api_key
      errors << "tracker.project_slug is required" unless tracker_project_slug
      errors << "codex.command is required" if codex_command.to_s.strip.empty?

      errors.empty? ? :ok : { error: :validation_error, messages: errors }
    end

    private

    def dig(*keys) = @config.dig(*keys)

    def integer_value(section, key, default)
      raw = dig(section, key)
      return default if raw.nil?
      Integer(raw)
    rescue ArgumentError, TypeError
      default
    end

    def resolve_env_var(value)
      return value unless value.is_a?(String) && value.start_with?("$")
      env_name = value[1..]
      result = ENV[env_name]
      result.nil? || result.empty? ? nil : result
    end

    def expand_path(path)
      return path unless path.is_a?(String)
      File.expand_path(path)
    end

    def parse_state_list(raw, default)
      case raw
      when Array then raw.map(&:to_s)
      when String then raw.split(",").map(&:strip)
      else default
      end
    end
  end
end
```

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/service_config_test.rb`

**Step 5: Commit**

```bash
git add app/models/symphony/service_config.rb test/models/symphony/service_config_test.rb
git commit -m "feat: add ServiceConfig typed layer with defaults and env resolution (SPEC 6.1-6.4)"
```

---

### Task 5: WorkflowStore — 파일 감시 + 동적 리로드 (SPEC 6.2)

**Files:**
- Create: `app/models/symphony/workflow_store.rb`
- Create: `test/models/symphony/workflow_store_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/workflow_store_test.rb
require "test_helper"
require "tempfile"

class Symphony::WorkflowStoreTest < ActiveSupport::TestCase
  setup do
    @file = Tempfile.new(["workflow", ".md"])
    @file.write("---\ntracker:\n  kind: linear\n---\nOriginal prompt")
    @file.close
    @store = Symphony::WorkflowStore.new(@file.path)
  end

  teardown do
    @file&.unlink
  end

  test "loads workflow on init" do
    assert_equal "linear", @store.config.dig("tracker", "kind")
    assert_equal "Original prompt", @store.prompt_template
  end

  test "returns ServiceConfig instance" do
    assert_instance_of Symphony::ServiceConfig, @store.service_config
    assert_equal "linear", @store.service_config.tracker_kind
  end

  test "detects file change and reloads" do
    File.write(@file.path, "---\ntracker:\n  kind: linear\n---\nUpdated prompt")
    @store.reload_if_changed!
    assert_equal "Updated prompt", @store.prompt_template
  end

  test "keeps last good config on invalid reload" do
    File.write(@file.path, "---\n- not a map\n---\nbad")
    @store.reload_if_changed!
    # Should keep original
    assert_equal "Original prompt", @store.prompt_template
  end

  test "force_reload always reloads" do
    File.write(@file.path, "---\ntracker:\n  kind: linear\n---\nForced")
    @store.force_reload!
    assert_equal "Forced", @store.prompt_template
  end
end
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/workflow_store_test.rb`

**Step 3: 구현**

```ruby
# app/models/symphony/workflow_store.rb
module Symphony
  class WorkflowStore
    attr_reader :config, :prompt_template, :path

    def initialize(path)
      @path = path
      @stamp = nil
      @config = {}
      @prompt_template = ""
      @mutex = Mutex.new
      load!
    end

    def service_config
      ServiceConfig.new(@config)
    end

    def reload_if_changed!
      @mutex.synchronize do
        current_stamp = compute_stamp
        if current_stamp != @stamp
          do_reload(current_stamp)
        end
      end
    end

    def force_reload!
      @mutex.synchronize do
        do_reload(compute_stamp)
      end
    end

    private

    def load!
      @mutex.synchronize do
        do_reload(compute_stamp)
      end
    end

    def do_reload(stamp)
      result = Workflow.load(@path)
      if result[:error]
        Rails.logger.error("[Symphony::WorkflowStore] Reload failed: #{result[:error]} #{result[:message]}")
        return
      end
      @config = result[:config]
      @prompt_template = result[:prompt_template]
      @stamp = stamp
      Rails.logger.info("[Symphony::WorkflowStore] Workflow reloaded from #{@path}")
    end

    def compute_stamp
      return nil unless File.exist?(@path)
      stat = File.stat(@path)
      content_hash = Zlib.crc32(File.read(@path))
      [stat.mtime, stat.size, content_hash]
    rescue => e
      Rails.logger.warn("[Symphony::WorkflowStore] Stamp computation failed: #{e.message}")
      nil
    end
  end
end
```

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/workflow_store_test.rb`

**Step 5: Commit**

```bash
git add app/models/symphony/workflow_store.rb test/models/symphony/workflow_store_test.rb
git commit -m "feat: add WorkflowStore with change detection and reload (SPEC 6.2)"
```

---

### Task 6: PromptBuilder — Liquid 템플릿 렌더링 (SPEC 5.4, 12.1–12.4)

**Files:**
- Create: `app/models/symphony/prompt_builder.rb`
- Create: `test/models/symphony/prompt_builder_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/prompt_builder_test.rb
require "test_helper"

class Symphony::PromptBuilderTest < ActiveSupport::TestCase
  test "renders issue fields into template" do
    template = "Working on {{ issue.identifier }}: {{ issue.title }}"
    issue = Symphony::Issue.new(id: "1", identifier: "MT-42", title: "Fix bug", state: "Todo")
    result = Symphony::PromptBuilder.render(template, issue: issue)
    assert_equal "Working on MT-42: Fix bug", result
  end

  test "renders attempt variable for retries" do
    template = "{% if attempt %}Retry #{{ attempt }}{% endif %}"
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
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/prompt_builder_test.rb`

**Step 3: 구현**

```ruby
# app/models/symphony/prompt_builder.rb
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

      result = template.render!(variables, strict_variables: true, strict_filters: true)
      result
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
```

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/prompt_builder_test.rb`

**Step 5: Commit**

```bash
git add app/models/symphony/prompt_builder.rb test/models/symphony/prompt_builder_test.rb
git commit -m "feat: add PromptBuilder with Liquid strict rendering (SPEC 5.4, 12.1-12.4)"
```

---

## Phase 3: Workspace Management

### Task 7: Workspace 매니저 (SPEC 9.1–9.5)

**Files:**
- Create: `app/models/symphony/workspace.rb`
- Create: `test/models/symphony/workspace_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/workspace_test.rb
require "test_helper"
require "tmpdir"

class Symphony::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("symphony_ws_test")
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "sanitizes identifier to safe workspace key" do
    assert_equal "MT-42", Symphony::Workspace.safe_identifier("MT-42")
    assert_equal "MT_42_special", Symphony::Workspace.safe_identifier("MT/42 special")
    assert_equal "issue", Symphony::Workspace.safe_identifier(nil)
  end

  test "creates new workspace directory" do
    ws = Symphony::Workspace.new(root: @root)
    result = ws.prepare("MT-42")
    assert result[:ok]
    assert result[:created]
    assert Dir.exist?(File.join(@root, "MT-42"))
  end

  test "reuses existing workspace" do
    ws = Symphony::Workspace.new(root: @root)
    ws.prepare("MT-42")
    result = ws.prepare("MT-42")
    assert result[:ok]
    refute result[:created]
  end

  test "rejects workspace path outside root" do
    ws = Symphony::Workspace.new(root: @root)
    result = ws.validate_path(File.join(@root, "..", "escape"))
    assert result[:error]
  end

  test "workspace path is deterministic per identifier" do
    ws = Symphony::Workspace.new(root: @root)
    path1 = ws.workspace_path("MT-42")
    path2 = ws.workspace_path("MT-42")
    assert_equal path1, path2
  end

  test "removes workspace with before_remove hook" do
    ws = Symphony::Workspace.new(root: @root)
    ws.prepare("MT-42")
    path = ws.workspace_path("MT-42")
    assert Dir.exist?(path)
    ws.remove("MT-42")
    refute Dir.exist?(path)
  end

  test "runs after_create hook on new workspace" do
    marker = File.join(@root, "hook_ran")
    ws = Symphony::Workspace.new(root: @root, hooks: { "after_create" => "touch #{marker}" }, hooks_timeout_ms: 5000)
    ws.prepare("MT-42")
    assert File.exist?(marker)
  end

  test "does not run after_create hook on existing workspace" do
    marker = File.join(@root, "hook_ran")
    ws = Symphony::Workspace.new(root: @root, hooks: { "after_create" => "touch #{marker}" }, hooks_timeout_ms: 5000)
    ws.prepare("MT-42")
    File.delete(marker)
    ws.prepare("MT-42")
    refute File.exist?(marker)
  end

  test "before_run hook failure returns error" do
    ws = Symphony::Workspace.new(root: @root, hooks: { "before_run" => "exit 1" }, hooks_timeout_ms: 5000)
    ws.prepare("MT-42")
    result = ws.run_before_run_hook("MT-42")
    assert result[:error]
  end

  test "after_run hook failure is ignored" do
    ws = Symphony::Workspace.new(root: @root, hooks: { "after_run" => "exit 1" }, hooks_timeout_ms: 5000)
    ws.prepare("MT-42")
    result = ws.run_after_run_hook("MT-42")
    assert_equal :ok, result
  end
end
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/workspace_test.rb`

**Step 3: 구현**

```ruby
# app/models/symphony/workspace.rb
module Symphony
  class Workspace
    SAFE_CHARS = /[^A-Za-z0-9._-]/

    attr_reader :root

    def initialize(root:, hooks: {}, hooks_timeout_ms: 60_000)
      @root = File.expand_path(root)
      @hooks = hooks
      @hooks_timeout_ms = hooks_timeout_ms
    end

    def self.safe_identifier(identifier)
      (identifier || "issue").to_s.gsub(SAFE_CHARS, "_")
    end

    def workspace_path(identifier)
      safe_id = self.class.safe_identifier(identifier)
      File.join(@root, safe_id)
    end

    def prepare(identifier)
      path = workspace_path(identifier)
      validation = validate_path(path)
      return validation if validation[:error]

      created = false
      if Dir.exist?(path)
        clean_tmp_artifacts(path)
      elsif File.exist?(path)
        FileUtils.rm_rf(path)
        FileUtils.mkdir_p(path)
        created = true
      else
        FileUtils.mkdir_p(path)
        created = true
      end

      if created && @hooks["after_create"]
        result = run_hook(@hooks["after_create"], path, "after_create")
        if result[:error]
          FileUtils.rm_rf(path)
          return result
        end
      end

      { ok: true, path: path, created: created }
    rescue => e
      { error: :workspace_creation_failed, message: e.message }
    end

    def remove(identifier)
      path = workspace_path(identifier)
      return unless File.exist?(path)

      validation = validate_path(path)
      return if validation[:error]

      if Dir.exist?(path) && @hooks["before_remove"]
        run_hook(@hooks["before_remove"], path, "before_remove") # ignore failure
      end

      FileUtils.rm_rf(path)
    end

    def run_before_run_hook(identifier)
      return :ok unless @hooks["before_run"]
      path = workspace_path(identifier)
      run_hook(@hooks["before_run"], path, "before_run")
    end

    def run_after_run_hook(identifier)
      return :ok unless @hooks["after_run"]
      path = workspace_path(identifier)
      run_hook(@hooks["after_run"], path, "after_run")
      :ok # always ignore failure
    end

    def validate_path(path)
      expanded = File.expand_path(path)
      root_prefix = File.expand_path(@root) + "/"

      if expanded == File.expand_path(@root)
        return { error: :workspace_equals_root }
      end

      unless expanded.start_with?(root_prefix)
        return { error: :workspace_outside_root }
      end

      { ok: true }
    end

    private

    def clean_tmp_artifacts(path)
      %w[tmp .elixir_ls].each do |entry|
        FileUtils.rm_rf(File.join(path, entry))
      end
    end

    def run_hook(command, workspace_path, hook_name)
      Rails.logger.info("[Symphony::Workspace] Running hook=#{hook_name} workspace=#{workspace_path}")

      pid = nil
      result = nil

      thread = Thread.new do
        stdout, stderr, status = Open3.capture3("sh", "-lc", command, chdir: workspace_path)
        result = { stdout: stdout, stderr: stderr, status: status }
      end

      unless thread.join(@hooks_timeout_ms / 1000.0)
        thread.kill
        Rails.logger.warn("[Symphony::Workspace] Hook timed out hook=#{hook_name} timeout_ms=#{@hooks_timeout_ms}")
        return { error: :hook_timeout, hook: hook_name }
      end

      if result[:status]&.success?
        :ok.then { { ok: true } }
      else
        Rails.logger.warn("[Symphony::Workspace] Hook failed hook=#{hook_name} status=#{result[:status]&.exitstatus}")
        { error: :hook_failed, hook: hook_name, status: result[:status]&.exitstatus }
      end
    rescue => e
      Rails.logger.error("[Symphony::Workspace] Hook error hook=#{hook_name} error=#{e.message}")
      { error: :hook_error, hook: hook_name, message: e.message }
    end
  end
end
```

Note: `Open3` require가 필요 — 파일 상단에 `require "open3"` 추가.

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/workspace_test.rb`

**Step 5: Commit**

```bash
git add app/models/symphony/workspace.rb test/models/symphony/workspace_test.rb
git commit -m "feat: add Workspace manager with hooks and safety invariants (SPEC 9.1-9.5)"
```

---

## Phase 4: Issue Tracker Integration

### Task 8: Tracker 어댑터 인터페이스 + Memory 어댑터 (SPEC 11.1)

**Files:**
- Create: `app/models/symphony/trackers/base.rb`
- Create: `app/models/symphony/trackers/memory.rb`
- Create: `test/models/symphony/trackers/memory_test.rb`

**Step 1: 테스트 작성**

```ruby
# test/models/symphony/trackers/memory_test.rb
require "test_helper"

class Symphony::Trackers::MemoryTest < ActiveSupport::TestCase
  setup do
    @issues = [
      Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Task 1", state: "Todo", priority: 2, created_at: Time.now),
      Symphony::Issue.new(id: "2", identifier: "MT-2", title: "Task 2", state: "In Progress", priority: 1, created_at: Time.now),
      Symphony::Issue.new(id: "3", identifier: "MT-3", title: "Task 3", state: "Done", priority: 3, created_at: Time.now),
    ]
    @tracker = Symphony::Trackers::Memory.new(issues: @issues)
  end

  test "fetch_candidate_issues returns active state issues" do
    result = @tracker.fetch_candidate_issues(active_states: ["Todo", "In Progress"])
    assert result[:ok]
    assert_equal 2, result[:issues].length
    identifiers = result[:issues].map(&:identifier)
    assert_includes identifiers, "MT-1"
    assert_includes identifiers, "MT-2"
  end

  test "fetch_issue_states_by_ids returns matching issues" do
    result = @tracker.fetch_issue_states_by_ids(["1", "3"])
    assert result[:ok]
    assert_equal 2, result[:issues].length
  end

  test "fetch_issues_by_states filters by normalized state" do
    result = @tracker.fetch_issues_by_states(["done"])
    assert result[:ok]
    assert_equal 1, result[:issues].length
    assert_equal "MT-3", result[:issues].first.identifier
  end

  test "fetch_issues_by_states with empty list returns empty" do
    result = @tracker.fetch_issues_by_states([])
    assert result[:ok]
    assert_empty result[:issues]
  end
end
```

**Step 2: 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/trackers/memory_test.rb`

**Step 3: 구현**

```ruby
# app/models/symphony/trackers/base.rb
module Symphony
  module Trackers
    class Base
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
```

```ruby
# app/models/symphony/trackers/memory.rb
module Symphony
  module Trackers
    class Memory < Base
      def initialize(issues: [])
        @issues = issues
      end

      def fetch_candidate_issues(active_states:)
        normalized = active_states.map { |s| s.to_s.strip.downcase }
        filtered = @issues.select { |i| normalized.include?(i.state.to_s.strip.downcase) }
        { ok: true, issues: filtered }
      end

      def fetch_issue_states_by_ids(ids)
        id_set = ids.to_set
        filtered = @issues.select { |i| id_set.include?(i.id) }
        { ok: true, issues: filtered }
      end

      def fetch_issues_by_states(states)
        return { ok: true, issues: [] } if states.empty?
        normalized = states.map { |s| s.to_s.strip.downcase }
        filtered = @issues.select { |i| normalized.include?(i.state.to_s.strip.downcase) }
        { ok: true, issues: filtered }
      end

      # Test helper: update issue state
      def update_issue_state(issue_id, new_state)
        # Memory adapter is immutable in production; this is for tests
      end
    end
  end
end
```

**Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/trackers/memory_test.rb`

**Step 5: Commit**

```bash
git add app/models/symphony/trackers/ test/models/symphony/trackers/
git commit -m "feat: add Tracker adapter interface + Memory adapter for testing (SPEC 11.1)"
```

---

### Task 9: Linear 트래커 클라이언트 (SPEC 11.2–11.4)

**Files:**
- Create: `app/models/symphony/trackers/linear.rb`
- Create: `test/models/symphony/trackers/linear_test.rb`

이 Task는 GraphQL 쿼리 구조, 페이지네이션, 이슈 정규화를 포함합니다.
Elixir POC의 `linear/client.ex`를 참조하여 동일한 쿼리 구조를 사용합니다.

핵심 구현:
- `SymphonyLinearPoll` 쿼리 (project slugId 필터, state name 필터, 커서 페이지네이션)
- `SymphonyLinearIssuesById` 쿼리 (ID 배치 필터, `[ID!]` 타입)
- 이슈 정규화 (labels lowercase, blockers from inverseRelations type=blocks)
- 에러 매핑 (transport, non-200, GraphQL errors)

테스트는 `webmock`으로 Linear API를 스텁합니다.

**Step 1–5:** 테스트 작성 → 실패 확인 → 구현 → 통과 → 커밋

커밋 메시지: `"feat: add Linear tracker client with GraphQL pagination (SPEC 11.2-11.4)"`

---

## Phase 5: Agent Runner Protocol

### Task 10: Agent 어댑터 인터페이스 (SPEC 10)

**Files:**
- Create: `app/models/symphony/agents/base.rb`

```ruby
# app/models/symphony/agents/base.rb
module Symphony
  module Agents
    class Base
      def start_session(workspace_path:, config:)
        raise NotImplementedError
      end

      # yields events via block: { event:, timestamp:, payload: }
      def run_turn(session:, prompt:, issue:, &on_message)
        raise NotImplementedError
      end

      def stop_session(session)
        raise NotImplementedError
      end
    end
  end
end
```

커밋: `"feat: add Agent adapter base interface (SPEC 10)"`

---

### Task 11: Codex App-Server 클라이언트 (SPEC 10.1–10.7)

**Files:**
- Create: `app/models/symphony/agents/codex.rb`
- Create: `app/models/symphony/agents/codex/protocol.rb`
- Create: `test/models/symphony/agents/codex_test.rb`

이것이 가장 복잡한 Task입니다. JSON-RPC stdio 프로토콜 구현:

핵심:
1. `bash -lc <command>`로 서브프로세스 실행
2. `initialize` → `initialized` → `thread/start` → `turn/start` 핸드셰이크
3. stdout에서 줄 단위 JSON 파싱 (stderr는 무시/로그)
4. `turn/completed`, `turn/failed`, `turn/cancelled` 이벤트 처리
5. Approval 자동 처리 (policy에 따라)
6. `user_input_required` → 즉시 실패
7. 타임아웃 (`read_timeout_ms`, `turn_timeout_ms`)

테스트는 mock subprocess 또는 fixture JSON 스트림으로 프로토콜 파싱을 검증합니다.

**Step 1–5:** 테스트 작성 → 실패 확인 → 구현 → 통과 → 커밋

커밋: `"feat: add Codex app-server JSON-RPC client (SPEC 10.1-10.7)"`

---

### Task 12: AgentRunner — 워크스페이스 + 프롬프트 + 에이전트 통합 (SPEC 10.7, 16.5)

**Files:**
- Create: `app/models/symphony/agent_runner.rb`
- Create: `test/models/symphony/agent_runner_test.rb`

워크스페이스 준비 → 훅 실행 → 세션 시작 → 턴 루프 (max_turns) → 세션 종료.
Elixir POC의 `agent_runner.ex`와 동일한 플로우.

커밋: `"feat: add AgentRunner with workspace + turn loop (SPEC 10.7, 16.5)"`

---

## Phase 6: Orchestration

### Task 13: Orchestrator 코어 — 상태 관리 + 디스패치 (SPEC 7–8)

**Files:**
- Create: `app/models/symphony/orchestrator.rb`
- Create: `test/models/symphony/orchestrator_test.rb`

핵심 상태:
```ruby
{
  running: {},          # issue_id => RunningEntry
  claimed: Set.new,     # issue_ids
  retry_attempts: {},   # issue_id => RetryEntry
  completed: Set.new,   # issue_ids (bookkeeping)
  codex_totals: { input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0.0 },
  codex_rate_limits: nil
}
```

핵심 메서드:
- `tick` — reconcile → validate → fetch → sort → dispatch
- `reconcile_running_issues` — stall 감지 + 트래커 상태 확인
- `should_dispatch?` — eligibility 검증 (claimed, slots, blockers)
- `dispatch_issue` — AgentWorkerJob enqueue
- `on_worker_exit` — normal → continuation retry, abnormal → backoff retry
- `on_retry_timer` — re-fetch + re-dispatch or release

테스트는 Memory tracker로 전체 디스패치/reconciliation 로직을 검증합니다.

커밋: `"feat: add Orchestrator core with dispatch and reconciliation (SPEC 7-8)"`

---

### Task 14: PollJob — Solid Queue recurring job (SPEC 8.1)

**Files:**
- Create: `app/jobs/symphony/poll_job.rb`
- Create: `test/jobs/symphony/poll_job_test.rb`

```ruby
# app/jobs/symphony/poll_job.rb
module Symphony
  class PollJob < ApplicationJob
    queue_as :symphony

    def perform
      orchestrator = Symphony.orchestrator
      orchestrator.tick
    end
  end
end
```

Solid Queue의 recurring job 설정 (`config/recurring.yml`):
```yaml
symphony_poll:
  class: Symphony::PollJob
  schedule: every 30 seconds
```

Note: 실제 poll interval은 WorkflowStore에서 동적으로 조정 — 기본 Solid Queue 스케줄은 fallback.

커밋: `"feat: add PollJob with Solid Queue recurring schedule (SPEC 8.1)"`

---

### Task 15: AgentWorkerJob — 에이전트 실행 job (SPEC 16.5)

**Files:**
- Create: `app/jobs/symphony/agent_worker_job.rb`
- Create: `test/jobs/symphony/agent_worker_job_test.rb`

```ruby
# app/jobs/symphony/agent_worker_job.rb
module Symphony
  class AgentWorkerJob < ApplicationJob
    queue_as :symphony_agents

    def perform(issue_id:, issue_identifier:, attempt: nil)
      runner = AgentRunner.new(
        tracker: Symphony.tracker,
        workspace: Symphony.workspace,
        agent: Symphony.agent,
        config: Symphony.config,
        on_event: ->(event) { Symphony.orchestrator.handle_codex_update(issue_id, event) }
      )
      runner.run(issue_id: issue_id, issue_identifier: issue_identifier, attempt: attempt)
    end
  end
end
```

커밋: `"feat: add AgentWorkerJob for Solid Queue agent execution (SPEC 16.5)"`

---

### Task 16: 재시도 큐 + 백오프 (SPEC 8.4)

**Files:**
- Create: `app/models/symphony/retry_scheduler.rb`
- Create: `test/models/symphony/retry_scheduler_test.rb`

핵심:
- Continuation retry: 1000ms (정상 종료 후)
- Failure retry: `min(10_000 * 2^(attempt-1), max_retry_backoff_ms)`
- Solid Queue의 `set(wait:)` 활용

커밋: `"feat: add RetryScheduler with exponential backoff (SPEC 8.4)"`

---

## Phase 7: Structured Logging

### Task 17: 구조화 로깅 (SPEC 13.1–13.2)

**Files:**
- Create: `app/models/symphony/logger.rb`
- Modify: `config/environments/production.rb` (log format)

핵심: Rails tagged logging으로 `issue_id`, `issue_identifier`, `session_id` 컨텍스트 부착.

```ruby
# app/models/symphony/logger.rb
module Symphony
  module Logger
    def self.with_issue(issue, &block)
      tags = {
        issue_id: issue.id || "n/a",
        issue_identifier: issue.identifier || "n/a"
      }
      Rails.logger.tagged(tags.map { |k, v| "#{k}=#{v}" }.join(" "), &block)
    end

    def self.with_session(session_id, &block)
      Rails.logger.tagged("session_id=#{session_id}", &block)
    end
  end
end
```

커밋: `"feat: add structured logging with issue/session context (SPEC 13.1-13.2)"`

---

## Phase 8: CLI Entry Point

### Task 18: bin/symphony CLI (SPEC 17.7)

**Files:**
- Create: `bin/symphony`
- Create: `test/cli/symphony_cli_test.rb`

```bash
#!/usr/bin/env ruby
# bin/symphony
require_relative "../config/environment"

workflow_path = ARGV[0] || File.join(Dir.pwd, "WORKFLOW.md")
logs_root = nil

ARGV.each_with_index do |arg, i|
  if arg == "--logs-root" && ARGV[i + 1]
    logs_root = ARGV[i + 1]
  end
end

unless File.exist?(workflow_path)
  $stderr.puts "Error: Workflow file not found: #{workflow_path}"
  exit 1
end

Symphony.boot!(workflow_path: workflow_path, logs_root: logs_root)
```

커밋: `"feat: add bin/symphony CLI entry point (SPEC 17.7)"`

---

## Phase 9: Integration & Boot

### Task 19: Symphony 모듈 — 부트스트랩 + 글로벌 액세스 (SPEC 16.1)

**Files:**
- Create: `app/models/symphony.rb` (또는 `lib/symphony.rb`)
- Create: `test/models/symphony_test.rb`

Singleton accessors:
- `Symphony.orchestrator`
- `Symphony.tracker`
- `Symphony.workspace`
- `Symphony.agent`
- `Symphony.config` (→ `workflow_store.service_config`)
- `Symphony.boot!(workflow_path:, logs_root:)`

`boot!` 시퀀스:
1. WorkflowStore 초기화 + validate
2. Startup terminal workspace cleanup
3. Orchestrator 초기화
4. Solid Queue worker 시작
5. File watcher 시작

커밋: `"feat: add Symphony boot sequence and global accessors (SPEC 16.1)"`

---

### Task 20: Startup terminal workspace cleanup (SPEC 8.6)

**Files:**
- Modify: `app/models/symphony.rb` (boot sequence)
- Create: `test/models/symphony/startup_cleanup_test.rb`

부팅 시 트래커에서 터미널 상태 이슈를 조회하고, 해당 workspace 디렉토리를 삭제합니다.

커밋: `"feat: add startup terminal workspace cleanup (SPEC 8.6)"`

---

## Phase 10: End-to-End Verification

### Task 21: 통합 테스트 — Memory tracker로 전체 흐름 검증

**Files:**
- Create: `test/integration/symphony_e2e_test.rb`

Memory tracker + mock agent로 전체 poll → dispatch → workspace → prompt → run → retry 사이클을 검증합니다.
SPEC Section 17 Test Matrix의 Core Conformance 항목을 모두 커버합니다.

커밋: `"test: add end-to-end integration test with memory tracker"`

---

### Task 22: SPEC 17 체크리스트 검증

**Files:**
- Create: `test/conformance/` 디렉토리

SPEC Section 17.1–17.7의 각 항목에 대한 테스트 존재 여부를 확인하고 누락된 테스트를 추가합니다.

커밋: `"test: verify SPEC 17 test matrix coverage"`

---

## Task Dependency Graph

```
Phase 1: [Task 1] Project Bootstrap
              ↓
Phase 2: [Task 2] Issue → [Task 3] Workflow → [Task 4] ServiceConfig → [Task 5] WorkflowStore → [Task 6] PromptBuilder
              ↓
Phase 3: [Task 7] Workspace
              ↓
Phase 4: [Task 8] Tracker Base+Memory → [Task 9] Linear Client
              ↓
Phase 5: [Task 10] Agent Base → [Task 11] Codex Client → [Task 12] AgentRunner
              ↓
Phase 6: [Task 13] Orchestrator → [Task 14] PollJob → [Task 15] AgentWorkerJob → [Task 16] RetryScheduler
              ↓
Phase 7: [Task 17] Logging
              ↓
Phase 8: [Task 18] CLI
              ↓
Phase 9: [Task 19] Boot → [Task 20] Startup Cleanup
              ↓
Phase 10: [Task 21] E2E Test → [Task 22] Conformance
```

## Parallelizable Tasks

Phase 내에서 독립적인 Task:
- Task 2, 3은 병렬 가능
- Task 8, 10은 병렬 가능 (둘 다 인터페이스 정의)
- Task 14, 15, 16, 17은 Task 13 이후 병렬 가능
