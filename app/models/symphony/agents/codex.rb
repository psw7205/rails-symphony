require "open3"
require "json"

module Symphony
  module Agents
    class Codex < Base
      INITIALIZE_ID = 1
      THREAD_START_ID = 2
      TURN_START_ID = 3

      def initialize(config:)
        @config = config
      end

      def start_session(workspace_path:, config: nil)
        cfg = config || @config
        command = cfg.codex_command

        stdin, stdout, stderr, wait_thread = Open3.popen3(
          "bash", "-lc", command,
          chdir: workspace_path
        )

        session = {
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          wait_thread: wait_thread,
          pid: wait_thread.pid,
          workspace: File.expand_path(workspace_path),
          read_timeout: cfg.codex_read_timeout_ms / 1000.0,
          turn_timeout: cfg.codex_turn_timeout_ms / 1000.0,
          approval_policy: cfg.codex_approval_policy || "never",
          thread_sandbox: cfg.codex_thread_sandbox || "locked-to-workspace",
          turn_sandbox_policy: cfg.codex_turn_sandbox_policy || { "type" => "locked-to-workspace" },
          thread_id: nil
        }

        # Drain stderr in background
        drain_stderr(stderr)

        # Handshake: initialize → initialized → thread/start
        send_initialize(session)
        response = read_response(session, INITIALIZE_ID)
        return { error: :initialize_failed, details: response } unless response && response["id"] == INITIALIZE_ID

        send_initialized(session)

        send_thread_start(session)
        thread_response = read_response(session, THREAD_START_ID)

        thread_id = thread_response&.dig("result", "thread", "id")
        return { error: :thread_start_failed, details: thread_response } unless thread_id

        session[:thread_id] = thread_id
        { ok: true, session: session }
      rescue => e
        Rails.logger.error("[Symphony::Agents::Codex] start_session failed: #{e.message}")
        { error: :session_start_failed, message: e.message }
      end

      def run_turn(session:, prompt:, issue:, &on_message)
        send_turn_start(session, prompt, issue)
        turn_response = read_response(session, TURN_START_ID)

        turn_id = turn_response&.dig("result", "turn", "id")
        unless turn_id
          emit(on_message, :startup_failed, { reason: :turn_start_failed, details: turn_response }, session)
          return { error: :turn_start_failed }
        end

        session_id = "#{session[:thread_id]}-#{turn_id}"
        emit(on_message, :session_started, {
          session_id: session_id, thread_id: session[:thread_id], turn_id: turn_id
        }, session)

        result = stream_turn(session, on_message)

        case result[:event]
        when :turn_completed
          { ok: true, event: :turn_completed, session_id: session_id,
            thread_id: session[:thread_id], turn_id: turn_id, usage: result[:usage] }
        when :turn_failed, :turn_cancelled
          { error: result[:event], session_id: session_id, details: result[:details] }
        else
          { error: result[:event] || :unknown, session_id: session_id }
        end
      rescue => e
        Rails.logger.error("[Symphony::Agents::Codex] run_turn failed: #{e.message}")
        { error: :turn_error, message: e.message }
      end

      def stop_session(session)
        return unless session

        session[:stdin]&.close rescue nil
        session[:stdout]&.close rescue nil
        session[:stderr]&.close rescue nil

        if session[:wait_thread]&.alive?
          Process.kill("TERM", session[:pid]) rescue nil
          session[:wait_thread].join(5)
          Process.kill("KILL", session[:pid]) rescue nil if session[:wait_thread]&.alive?
        end
      end

      private

        def send_message(session, payload)
          json = JSON.generate(payload)
          session[:stdin].puts(json)
          session[:stdin].flush
        end

        def read_response(session, expected_id)
          deadline = Time.now + session[:read_timeout]
          buffer = +""

          while Time.now < deadline
            ready = IO.select([session[:stdout]], nil, nil, 0.1)
            next unless ready

            chunk = session[:stdout].read_nonblock(65536) rescue nil
            break unless chunk
            buffer << chunk

            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0..line_end).strip
              next if line.empty?

              parsed = JSON.parse(line) rescue nil
              next unless parsed

              # Skip notifications (no id field)
              if parsed["id"] == expected_id
                return parsed
              end

              # Handle other messages that arrive before our response
              handle_interim_message(session, parsed)
            end
          end

          nil
        end

        def stream_turn(session, on_message)
          deadline = Time.now + session[:turn_timeout]
          buffer = +""

          while Time.now < deadline
            # Check if process exited
            unless session[:wait_thread].alive?
              return { event: :process_exit, details: session[:wait_thread].value }
            end

            ready = IO.select([session[:stdout]], nil, nil, 0.5)
            next unless ready

            chunk = begin
              session[:stdout].read_nonblock(65536)
            rescue EOFError
              return { event: :process_exit }
            rescue IOError
              return { event: :process_exit }
            end

            buffer << chunk

            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0..line_end).strip
              next if line.empty?

              parsed = begin
                JSON.parse(line)
              rescue JSON::ParserError
                emit(on_message, :malformed, { raw: line }, session)
                next
              end

              case parsed["method"]
              when "turn/completed"
                usage = extract_usage(parsed)
                emit(on_message, :turn_completed, { payload: parsed, usage: usage }, session)
                return { event: :turn_completed, usage: usage }
              when "turn/failed"
                emit(on_message, :turn_failed, { payload: parsed }, session)
                return { event: :turn_failed, details: parsed["params"] }
              when "turn/cancelled"
                emit(on_message, :turn_cancelled, { payload: parsed }, session)
                return { event: :turn_cancelled, details: parsed["params"] }
              else
                handle_stream_message(session, parsed, on_message)
              end
            end
          end

          { event: :turn_timeout }
        end

        def handle_stream_message(session, parsed, on_message)
          method = parsed["method"]

          case method
          when "item/approval/request"
            handle_approval(session, parsed, on_message)
          when "item/tool/call"
            handle_tool_call(session, parsed, on_message)
          when "user_input_required"
            emit(on_message, :turn_input_required, { payload: parsed }, session)
          else
            emit(on_message, :notification, { method: method, payload: parsed }, session)
          end
        end

        def handle_approval(session, parsed, on_message)
          approval_id = parsed["id"] || parsed.dig("params", "id")
          if approval_id && session[:approval_policy] == "never"
            send_message(session, { "id" => approval_id, "result" => { "approved" => true } })
            emit(on_message, :approval_auto_approved, { id: approval_id }, session)
          end
        end

        def handle_tool_call(session, parsed, on_message)
          tool_call_id = parsed["id"]
          if tool_call_id
            send_message(session, {
              "id" => tool_call_id,
              "result" => { "success" => false, "error" => "unsupported_tool_call" }
            })
            emit(on_message, :unsupported_tool_call, { id: tool_call_id, payload: parsed }, session)
          end
        end

        def handle_interim_message(session, parsed)
          # Silently skip notifications during handshake
        end

        def extract_usage(parsed)
          params = parsed["params"] || {}
          usage = params["usage"] || {}
          {
            input_tokens: usage["input_tokens"] || usage["inputTokens"],
            output_tokens: usage["output_tokens"] || usage["outputTokens"],
            total_tokens: usage["total_tokens"] || usage["totalTokens"]
          }
        end

        def emit(on_message, event, payload, session)
          return unless on_message
          on_message.call({
            event: event,
            timestamp: Time.now.utc,
            codex_app_server_pid: session[:pid],
            **payload
          })
        end

        def drain_stderr(stderr)
          Thread.new do
            while (line = stderr.gets rescue nil)
              Rails.logger.debug("[Symphony::Agents::Codex][stderr] #{line.chomp}")
            end
          end
        end

        def send_initialize(session)
          send_message(session, {
            "id" => INITIALIZE_ID,
            "method" => "initialize",
            "params" => {
              "clientInfo" => { "name" => "symphony", "version" => "1.0" },
              "capabilities" => {}
            }
          })
        end

        def send_initialized(session)
          send_message(session, { "method" => "initialized", "params" => {} })
        end

        def send_thread_start(session)
          send_message(session, {
            "id" => THREAD_START_ID,
            "method" => "thread/start",
            "params" => {
              "approvalPolicy" => session[:approval_policy],
              "sandbox" => session[:thread_sandbox],
              "cwd" => session[:workspace]
            }
          })
        end

        def send_turn_start(session, prompt, issue)
          send_message(session, {
            "id" => TURN_START_ID,
            "method" => "turn/start",
            "params" => {
              "threadId" => session[:thread_id],
              "input" => [{ "type" => "text", "text" => prompt }],
              "cwd" => session[:workspace],
              "title" => "#{issue.identifier}: #{issue.title}",
              "approvalPolicy" => session[:approval_policy],
              "sandboxPolicy" => session[:turn_sandbox_policy]
            }
          })
        end
    end
  end
end
