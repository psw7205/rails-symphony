# Symphony Rails Implementation Design

Status: Approved
Date: 2026-03-05
Ref: `symphony/SPEC.md` (Draft v1)

## Overview

Rails 8 + SQLite + Solid Queue 기반 Symphony 구현.
SPEC.md Section 18.1 (Core Conformance) 완전 준수가 1차 목표.
Elixir POC(`symphony/elixir/`)를 참조 구현으로 활용.

## Decisions

| 항목 | 결정 |
|------|------|
| Framework | Rails 8, SQLite, Solid Queue |
| Agent | 어댑터 패턴 — Codex 우선, Claude Code 2차 |
| Tracker | 어댑터 패턴 — Linear 우선, GitHub Issues 2차 |
| Observability | 1차: 구조화 로그만. 웹 UI/API는 2차 |
| State | SQLite 영속화 (SPEC in-memory 상위호환, 재시작 복구 포함) |
| Project root | `rails-symphony/` 자체가 Rails 앱 |

## Architecture

SPEC 6개 계층을 Rails 컨벤션에 매핑:

```
Policy Layer        → WORKFLOW.md (repo-owned)
Configuration Layer → app/models/workflow.rb, app/models/service_config.rb
Coordination Layer  → app/jobs/poll_job.rb, app/models/orchestrator.rb
Execution Layer     → app/jobs/agent_worker_job.rb, app/models/workspace.rb
Integration Layer   → app/models/trackers/linear.rb
Observability Layer → Rails.logger + structured tags
```

### Component Mapping (SPEC → Rails)

| SPEC Component | Rails Implementation |
|---|---|
| Workflow Loader | `Workflow` model — YAML front matter + Liquid body 파싱 |
| Config Layer | `ServiceConfig` model — typed getters, defaults, `$VAR`/`~` 확장 |
| Issue Tracker Client | `Trackers::Base` (interface) + `Trackers::Linear` |
| Orchestrator | `Orchestrator` model — in-memory + DB hybrid state |
| Workspace Manager | `Workspace` model — sanitize, hooks, safety invariants |
| Agent Runner | `Agents::Base` (interface) + `Agents::Codex` |
| Status Surface | 1차 제외 (2차에서 Turbo/Hotwire 대시보드) |
| Logging | `Rails.logger` with tagged logging |

### Adapter Interfaces

**Trackers::Base**
- `#fetch_candidate_issues` → Issue 목록 (active states, project filter)
- `#fetch_issue_states_by_ids(ids)` → reconciliation용 상태 조회
- `#fetch_issues_by_states(states)` → startup terminal cleanup

**Agents::Base**
- `#start_session(workspace_path:, config:)` → 세션 시작
- `#run_turn(thread_id:, prompt:, callbacks:)` → 턴 실행, 이벤트 스트리밍
- `#stop_session` → 세션 종료, 프로세스 정리

### DB Schema (SQLite)

```
issues
  - id (string, tracker internal ID)
  - identifier (string, e.g. "ABC-123")
  - title, description, priority, state
  - branch_name, url, labels (JSON), blocked_by (JSON)
  - created_at, updated_at

run_attempts
  - issue_id (FK)
  - attempt (integer)
  - workspace_path
  - status (enum: preparing_workspace..canceled_by_reconciliation)
  - error (text, nullable)
  - started_at, finished_at

agent_sessions
  - run_attempt_id (FK)
  - session_id (string, "<thread_id>-<turn_id>")
  - thread_id, turn_id
  - codex_app_server_pid
  - last_codex_event, last_codex_timestamp, last_codex_message
  - codex_input_tokens, codex_output_tokens, codex_total_tokens
  - turn_count

retry_entries
  - issue_id (string)
  - identifier (string)
  - attempt (integer)
  - due_at (datetime)
  - error (text, nullable)

orchestrator_states (singleton row)
  - codex_total_input_tokens, codex_total_output_tokens, codex_total_tokens
  - codex_total_seconds_running
  - codex_rate_limits (JSON)
```

### Core Flow

```
PollJob (Solid Queue recurring job)
  → Orchestrator.tick
    1. reconcile_running_issues
       - stall detection (stall_timeout_ms)
       - tracker state refresh → terminate/update/release
    2. validate_dispatch_config
    3. tracker.fetch_candidate_issues
    4. sort_for_dispatch (priority ASC, created_at ASC, identifier ASC)
    5. filter eligible (not claimed, slots available, blocker rules)
    6. dispatch → AgentWorkerJob.perform_later

AgentWorkerJob (Solid Queue job)
  → Workspace.prepare(issue)
    - sanitize identifier → workspace_key
    - ensure directory under workspace root
    - run after_create hook (if new)
  → run before_run hook
  → Agents::Codex.start_session
  → turn loop (1..max_turns)
    - build prompt (Liquid, first turn: full prompt, continuation: guidance)
    - run_turn (JSON-RPC stdio streaming)
    - emit events to Orchestrator
    - refresh issue state from tracker
    - break if not active or max_turns reached
  → Agents::Codex.stop_session
  → run after_run hook
  → report result to Orchestrator
    - normal exit → continuation retry (1s delay)
    - abnormal exit → exponential backoff retry
```

### Codex App-Server Protocol (JSON-RPC over stdio)

SPEC Section 10 그대로 구현:
1. `initialize` request → wait response
2. `initialized` notification
3. `thread/start` → get thread_id
4. `turn/start` → streaming until turn/completed|failed|cancelled
5. Handle approvals, tool calls, user-input-required per policy

### Workspace Safety Invariants (SPEC Section 9.5)

1. Agent cwd == workspace_path (반드시 검증)
2. workspace_path는 workspace_root 하위 (절대경로 prefix 검증)
3. workspace_key는 `[A-Za-z0-9._-]`만 허용 (나머지 → `_`)

### WORKFLOW.md Dynamic Reload

- `Listen` gem 또는 `ActiveSupport::FileUpdateChecker`로 파일 변경 감시
- 변경 시 re-parse, re-validate, apply to future dispatches
- 유효하지 않은 리로드는 마지막 정상 config 유지 + 에러 로그

### CLI Entry Point

```bash
bin/symphony WORKFLOW.md [--logs-root ./log]
```

- Rails runner 기반 또는 standalone script
- Solid Queue worker를 같은 프로세스에서 실행

## 1차 구현 범위 (Core Conformance, SPEC 18.1)

1. WORKFLOW.md 로더 — YAML front matter + prompt body split
2. Config 레이어 — typed getters, defaults, `$VAR`/`~` 확장
3. WORKFLOW.md 파일 감시 + 동적 리로드
4. Orchestrator — poll tick, dispatch, reconciliation, state machine
5. Linear 트래커 클라이언트 — GraphQL candidate fetch, state refresh, terminal fetch
6. Workspace 매니저 — sanitize, hooks (after_create, before_run, after_run, before_remove), safety
7. Codex app-server 클라이언트 — JSON-RPC stdio, turn loop, event streaming
8. Liquid 프롬프트 렌더링 — strict mode, `issue`/`attempt` 변수
9. 재시도 큐 — exponential backoff + continuation retry (1s)
10. Reconciliation — stall 감지 + terminal/non-active 상태 처리
11. 구조화 로그 — `issue_id`, `issue_identifier`, `session_id` 태그
12. CLI — `bin/symphony WORKFLOW.md`
13. Startup terminal workspace cleanup

## 2차 확장 (구현하지 않고 인터페이스만 준비)

- `Agents::ClaudeCode` 어댑터
- `Trackers::GithubIssues` 어댑터
- HTTP JSON API (`/api/v1/state`, `/api/v1/<issue>`, `/api/v1/refresh`)
- Turbo/Hotwire 실시간 대시보드
- `linear_graphql` client-side tool extension
- Retry 큐 재시작 복구 (DB 기반이므로 자연스럽게 가능)

## Key Dependencies

- `rails` 8.x
- `solid_queue` — background job
- `liquid` — template rendering
- `listen` — file watching (또는 ActiveSupport::FileUpdateChecker)
- `httpx` 또는 `faraday` — Linear GraphQL HTTP client
- `sqlite3` — database
