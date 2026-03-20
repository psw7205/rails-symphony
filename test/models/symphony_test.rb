require "test_helper"
require "tmpdir"

class SymphonyTest < ActiveSupport::TestCase
  test "config delegates to workflow_store" do
    root = Dir.mktmpdir("symphony_test")
    workflow_file = File.join(root, "WORKFLOW.md")
    File.write(workflow_file, "---\ntracker:\n  kind: linear\n  api_key: test\n  project_slug: proj\n---\nHello")

    store = Symphony::WorkflowStore.new(workflow_file)
    Symphony.workflow_store = store

    assert_instance_of Symphony::ServiceConfig, Symphony.config
    assert_equal "linear", Symphony.config.tracker_kind
  ensure
    FileUtils.rm_rf(root)
    Symphony.workflow_store = nil
  end

  test "boot! keeps the legacy workflow path working" do
    root = Dir.mktmpdir("symphony_boot")
    workflow_file = File.join(root, "WORKFLOW.md")
    workspace_root = File.join(root, "workspaces")
    File.write(workflow_file, <<~WORKFLOW)
      ---
      tracker:
        kind: memory
      workspace:
        root: #{workspace_root}
      ---
      Hello
    WORKFLOW

    listener = Object.new
    listener.define_singleton_method(:start) { true }
    codex_singleton = class << Symphony::Agents::Codex; self; end
    listen_singleton = class << Listen; self; end

    codex_singleton.alias_method :__legacy_boot_test_new, :new
    listen_singleton.alias_method :__legacy_boot_test_to, :to

    codex_singleton.define_method(:new) { |*args, **kwargs| Symphony::Agents::Base.new }
    listen_singleton.define_method(:to) { |*args, **kwargs, &block| listener }

    Symphony.boot!(workflow_path: workflow_file)

    assert_instance_of Symphony::WorkflowStore, Symphony.workflow_store
    assert_instance_of Symphony::Orchestrator, Symphony.orchestrator
    assert_instance_of Symphony::Trackers::Memory, Symphony.tracker
    assert_equal "memory", Symphony.config.tracker_kind
    assert_equal workspace_root, Symphony.workspace.root
  ensure
    FileUtils.rm_rf(root)
    Symphony.workflow_store = nil
    Symphony.orchestrator = nil
    Symphony.tracker = nil
    Symphony.workspace = nil
    Symphony.agent = nil
    if defined?(codex_singleton) && codex_singleton.method_defined?(:__legacy_boot_test_new)
      codex_singleton.alias_method :new, :__legacy_boot_test_new
      codex_singleton.remove_method :__legacy_boot_test_new
    end
    if defined?(listen_singleton) && listen_singleton.method_defined?(:__legacy_boot_test_to)
      listen_singleton.alias_method :to, :__legacy_boot_test_to
      listen_singleton.remove_method :__legacy_boot_test_to
    end
  end
end
