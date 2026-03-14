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

  # SPEC 17.2: Temporary artifacts removed during prep
  test "removes tmp and .elixir_ls artifacts on existing workspace prep" do
    ws = Symphony::Workspace.new(root: @root)
    ws.prepare("MT-42")
    path = ws.workspace_path("MT-42")

    FileUtils.mkdir_p(File.join(path, "tmp"))
    FileUtils.mkdir_p(File.join(path, ".elixir_ls"))
    File.write(File.join(path, "tmp", "junk"), "data")

    ws.prepare("MT-42")
    refute Dir.exist?(File.join(path, "tmp"))
    refute Dir.exist?(File.join(path, ".elixir_ls"))
  end

  # SPEC 17.2: Non-directory path at workspace location is handled safely
  test "replaces non-directory file at workspace location" do
    ws = Symphony::Workspace.new(root: @root)
    file_path = File.join(@root, "MT-42")
    File.write(file_path, "not a directory")

    result = ws.prepare("MT-42")
    assert result[:ok]
    assert result[:created]
    assert Dir.exist?(file_path)
  end

  # SPEC 17.2: before_remove hook runs on cleanup
  test "runs before_remove hook on workspace removal" do
    marker = File.join(@root, "remove_hook_ran")
    ws = Symphony::Workspace.new(root: @root, hooks: { "before_remove" => "touch #{marker}" }, hooks_timeout_ms: 5000)
    ws.prepare("MT-42")
    ws.remove("MT-42")
    assert File.exist?(marker)
  end

  # SPEC 17.2: before_remove hook failure is ignored
  test "before_remove hook failure does not prevent removal" do
    ws = Symphony::Workspace.new(root: @root, hooks: { "before_remove" => "exit 1" }, hooks_timeout_ms: 5000)
    ws.prepare("MT-42")
    path = ws.workspace_path("MT-42")
    ws.remove("MT-42")
    refute Dir.exist?(path)
  end
end
