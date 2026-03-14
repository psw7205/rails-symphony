require "test_helper"
require "tempfile"

class Symphony::WorkflowStoreTest < ActiveSupport::TestCase
  setup do
    @file = Tempfile.new([ "workflow", ".md" ])
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
    assert_nil @store.last_error
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
    assert_equal "Original prompt", @store.prompt_template
    assert_equal :workflow_front_matter_not_a_map, @store.last_error
  end

  test "force_reload always reloads" do
    File.write(@file.path, "---\ntracker:\n  kind: linear\n---\nForced")
    @store.force_reload!
    assert_equal "Forced", @store.prompt_template
  end
end
