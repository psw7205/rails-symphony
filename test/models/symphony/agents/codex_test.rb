require "test_helper"
require "json"
require "tmpdir"

class Symphony::Agents::CodexTest < ActiveSupport::TestCase
  test "full handshake and turn completion" do
    workspace = Dir.mktmpdir("codex_test")
    script = write_mock_server(workspace, <<~'BASH')
      #!/usr/bin/env bash
      read line; echo '{"id":1,"result":{"serverInfo":{"name":"test"}}}'
      read line
      read line; echo '{"id":2,"result":{"thread":{"id":"thread-abc"}}}'
      read line; echo '{"id":3,"result":{"turn":{"id":"turn-xyz"}}}'
      sleep 0.1
      echo '{"method":"turn/completed","params":{"usage":{"input_tokens":10,"output_tokens":20,"total_tokens":30}}}'
    BASH

    codex = build_codex(script)
    result = codex.start_session(workspace_path: workspace)
    assert result[:ok], "start_session failed: #{result.inspect}"
    assert_equal "thread-abc", result[:session][:thread_id]

    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Test", state: "Todo")
    events = []
    turn_result = codex.run_turn(session: result[:session], prompt: "Hello", issue: issue) { |e| events << e }

    assert turn_result[:ok], "run_turn failed: #{turn_result.inspect}"
    assert_equal :turn_completed, turn_result[:event]
    assert_includes events.map { |e| e[:event] }, :session_started
    assert_includes events.map { |e| e[:event] }, :turn_completed

    codex.stop_session(result[:session])
  ensure
    FileUtils.rm_rf(workspace)
  end

  test "stop_session terminates process" do
    workspace = Dir.mktmpdir("codex_stop_test")
    script = write_mock_server(workspace, <<~'BASH')
      #!/usr/bin/env bash
      read line; echo '{"id":1,"result":{"serverInfo":{"name":"test"}}}'
      read line
      read line; echo '{"id":2,"result":{"thread":{"id":"t1"}}}'
      sleep 300
    BASH

    codex = build_codex(script)
    result = codex.start_session(workspace_path: workspace)
    assert result[:ok]

    pid = result[:session][:pid]
    codex.stop_session(result[:session])
    sleep 0.3

    alive = begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
    refute alive, "Process should be terminated"
  ensure
    FileUtils.rm_rf(workspace)
  end

  test "auto-approves when policy is never" do
    workspace = Dir.mktmpdir("codex_approval_test")
    script = write_mock_server(workspace, <<~'BASH')
      #!/usr/bin/env bash
      read line; echo '{"id":1,"result":{"serverInfo":{"name":"test"}}}'
      read line
      read line; echo '{"id":2,"result":{"thread":{"id":"t1"}}}'
      read line; echo '{"id":3,"result":{"turn":{"id":"turn1"}}}'
      sleep 0.1
      echo '{"method":"item/approval/request","id":"approval-1","params":{"type":"command"}}'
      sleep 0.5
      echo '{"method":"turn/completed","params":{"usage":{}}}'
    BASH

    codex = build_codex(script)
    result = codex.start_session(workspace_path: workspace)
    assert result[:ok]

    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Test", state: "Todo")
    events = []
    turn_result = codex.run_turn(session: result[:session], prompt: "test", issue: issue) { |e| events << e }

    assert turn_result[:ok]
    assert_includes events.map { |e| e[:event] }, :approval_auto_approved

    codex.stop_session(result[:session])
  ensure
    FileUtils.rm_rf(workspace)
  end

  test "handles turn failure" do
    workspace = Dir.mktmpdir("codex_fail_test")
    script = write_mock_server(workspace, <<~'BASH')
      #!/usr/bin/env bash
      read line; echo '{"id":1,"result":{"serverInfo":{"name":"test"}}}'
      read line
      read line; echo '{"id":2,"result":{"thread":{"id":"t1"}}}'
      read line; echo '{"id":3,"result":{"turn":{"id":"turn1"}}}'
      sleep 0.1
      echo '{"method":"turn/failed","params":{"reason":"agent_error"}}'
    BASH

    codex = build_codex(script)
    result = codex.start_session(workspace_path: workspace)
    assert result[:ok]

    issue = Symphony::Issue.new(id: "1", identifier: "MT-1", title: "Test", state: "Todo")
    events = []
    turn_result = codex.run_turn(session: result[:session], prompt: "test", issue: issue) { |e| events << e }

    assert_equal :turn_failed, turn_result[:error]
    assert_includes events.map { |e| e[:event] }, :turn_failed

    codex.stop_session(result[:session])
  ensure
    FileUtils.rm_rf(workspace)
  end

  private

    def write_mock_server(workspace, script_content)
      path = File.join(workspace, "mock_server.sh")
      File.write(path, script_content)
      File.chmod(0o755, path)
      path
    end

    def build_codex(script_path)
      config = Symphony::ServiceConfig.new({
        "codex" => {
          "command" => script_path,
          "read_timeout_ms" => 3000,
          "turn_timeout_ms" => 5000,
          "approval_policy" => "never"
        }
      })
      Symphony::Agents::Codex.new(config: config)
    end
end
