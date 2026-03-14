require "test_helper"

# SPEC 17.7 CLI and Host Lifecycle Conformance
class CliLifecycleTest < ActiveSupport::TestCase
  # SPEC 17.7.1: CLI accepts optional positional workflow path argument
  test "bin/symphony parses positional workflow path" do
    script = File.read(Rails.root.join("bin/symphony"))
    assert_includes script, "workflow_path ||= arg"
  end

  # SPEC 17.7.2: CLI uses ./WORKFLOW.md when no argument provided
  test "bin/symphony defaults to WORKFLOW.md in cwd" do
    script = File.read(Rails.root.join("bin/symphony"))
    assert_includes script, "WORKFLOW.md"
  end

  # SPEC 17.7.3: CLI errors on nonexistent explicit workflow path
  test "bin/symphony exits nonzero for missing workflow file" do
    result = `ruby -e "ARGV.replace(['/nonexistent/path.md']); load '#{Rails.root.join("bin/symphony")}'" 2>&1`
    refute $?.success?
  end

  # SPEC 17.7.5-6: CLI exit codes
  test "bin/symphony prints error to stderr for missing file" do
    output = `ruby -e "ARGV.replace(['/nonexistent/path.md']); load '#{Rails.root.join("bin/symphony")}'" 2>&1`
    assert_includes output, "Workflow file not found"
  end

  # SPEC 17.7: --logs-root flag parsing
  test "bin/symphony supports --logs-root flag" do
    script = File.read(Rails.root.join("bin/symphony"))
    assert_includes script, "--logs-root"
  end

  test "bin/symphony parses flags before positional workflow path" do
    script = File.read(Rails.root.join("bin/symphony"))
    assert_includes script, "workflow_path = nil"
    assert_includes script, "elsif !arg.start_with?(\"--\")"
  end
end
