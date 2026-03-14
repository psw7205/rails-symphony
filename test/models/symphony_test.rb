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
end
