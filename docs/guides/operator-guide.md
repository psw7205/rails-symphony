# Symphony 운영 가이드

Symphony를 설정하고 실행하는 방법을 다룬다.
내부 동작 원리는 [기능 동작 레퍼런스](feature-reference.md)를 참고한다.

---

## 1. 빠른 시작

### 사전 요구사항

- Ruby 3.2+, Rails 8
- SQLite3
- Codex CLI (`codex app-server` 명령 사용 가능)
- Linear API 키 (Linear 트래커 사용 시)

### 셋업

```bash
bin/setup --skip-server
```

### 최소 WORKFLOW.md

대상 저장소 루트에 `WORKFLOW.md`를 생성한다.

```yaml
---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: MY-PROJECT

agent:
  max_concurrent_agents: 2
---

{{ issue.identifier }}: {{ issue.title }}

{{ issue.description }}
```

### 실행

```bash
bin/symphony                          # 현재 디렉토리의 WORKFLOW.md 사용
bin/symphony /path/to/WORKFLOW.md     # 경로 지정
bin/symphony --port 3001              # 서버 포트 지정
bin/symphony --logs-root /var/log/sym # 로그 디렉토리 지정
```

실행하면 오케스트레이터가 기동되고, 설정된 주기(`polling.interval_ms`)마다 트래커를 폴링하여 이슈를 디스패치한다.

---

## 2. WORKFLOW.md 작성법

YAML front matter + Liquid 템플릿 본문으로 구성된 단일 파일 설정이다.

### 2.1 YAML 설정 키 레퍼런스

#### tracker

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `kind` | string | *필수* | `linear` 또는 `memory` |
| `api_key` | string | `$LINEAR_API_KEY` | API 키. `$ENV_VAR` 형태로 환경변수 참조 가능 |
| `endpoint` | string | `https://api.linear.app/graphql` | GraphQL 엔드포인트 |
| `project_slug` | string | *필수(linear)* | Linear 프로젝트 슬러그 |
| `active_states` | array | `[Todo, In Progress]` | 디스패치 대상 이슈 상태 |
| `terminal_states` | array | `[Closed, Cancelled, Canceled, Duplicate, Done]` | 종료 상태 (워크스페이스 자동 정리) |

#### polling

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `interval_ms` | int | `30000` | 폴링 주기 (밀리초) |

#### workspace

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `root` | string | `$TMPDIR/symphony_workspaces` | 워크스페이스 루트 디렉토리. `~`, `$ENV_VAR` 확장 지원 |

#### hooks

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `after_create` | string | — | 워크스페이스 최초 생성 시 실행. 실패 시 워크스페이스 삭제 |
| `before_remove` | string | — | 워크스페이스 삭제 직전 실행 |
| `before_run` | string | — | 에이전트 세션 시작 직전 실행 |
| `after_run` | string | — | 에이전트 세션 완료 후 실행 |
| `timeout_ms` | int | `60000` | 훅 실행 타임아웃 (밀리초) |

모든 훅은 워크스페이스 디렉토리를 working directory로 실행된다 (`sh -lc`).

#### agent

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `max_concurrent_agents` | int | `10` | 전체 동시 실행 에이전트 수 상한 |
| `max_concurrent_agents_by_state` | map | — | 상태별 동시 실행 제한 (예: `todo: 2`) |
| `max_turns` | int | `20` | 에이전트 세션당 최대 턴 수 |
| `max_retry_backoff_ms` | int | `300000` | 재시도 백오프 상한 (밀리초) |

#### codex

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `command` | string | `codex app-server` | Codex 실행 명령 |
| `approval_policy` | string | — | `never` 설정 시 승인 요청 자동 수락 |
| `thread_sandbox` | string | — | 스레드 샌드박스 설정 |
| `turn_sandbox_policy` | string | — | 턴 샌드박스 정책 |
| `turn_timeout_ms` | int | `3600000` | 턴 타임아웃 (1시간) |
| `read_timeout_ms` | int | `5000` | 응답 읽기 타임아웃 |
| `stall_timeout_ms` | int | `300000` | 무응답 감지 임계치 (5분) |

#### server

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `port` | int | Rails 기본 | HTTP 서버 포트. CLI `--port`가 우선 |

### 2.2 환경변수 치환

YAML 값이 `$`로 시작하면 해당 환경변수로 치환된다.

```yaml
tracker:
  api_key: $LINEAR_API_KEY    # → ENV["LINEAR_API_KEY"]
workspace:
  root: $SYMPHONY_WORKSPACE   # → ENV["SYMPHONY_WORKSPACE"]
```

`~`는 `File.expand_path`로 홈 디렉토리 확장된다.

### 2.3 Liquid 템플릿 변수

본문에서 사용 가능한 변수:

| 변수 | 타입 | 설명 |
|---|---|---|
| `issue.id` | string | 트래커 내부 ID |
| `issue.identifier` | string | 사람이 읽는 식별자 (예: `PRJ-123`) |
| `issue.title` | string | 이슈 제목 |
| `issue.description` | string | 이슈 본문 |
| `issue.priority` | int | 우선순위 (낮을수록 높은 순위) |
| `issue.state` | string | 현재 상태명 |
| `issue.branch_name` | string | 연결된 브랜치명 |
| `issue.url` | string | 이슈 URL |
| `issue.labels` | array | 레이블 목록 (소문자) |
| `issue.blocked_by` | array | 이 이슈를 차단하는 이슈 ID 목록 |
| `issue.created_at` | string | 생성 시각 (ISO 8601) |
| `issue.updated_at` | string | 갱신 시각 (ISO 8601) |
| `attempt` | int/nil | 재시도 횟수 |

Liquid strict mode이므로 오타나 미정의 변수는 에러를 발생시킨다.

### 2.4 동적 리로드

WORKFLOW.md 파일 변경 시 자동 감지하여 리로드된다.

- 감지 방식: `Listen` gem (파일 시스템 이벤트) + stamp 검증 (mtime, size, CRC32)
- 리로드 실패 시 기존 설정 유지, 에러 로그 출력
- 다음 tick에서 validation 통과 시 새 설정 적용

---

## 3. 트래커 설정

### Linear

```yaml
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: MY-PROJECT
  active_states: [Todo, In Progress]
  terminal_states: [Done, Cancelled]
```

- GraphQL 커서 기반 페이지네이션 (50건/페이지)
- `inverseRelations`으로 blocker 관계 추출
- 레이블은 소문자로 정규화

### Memory (테스트용)

```yaml
tracker:
  kind: memory
```

인메모리 배열 기반. 테스트 코드에서 `Trackers::Memory#add_issue`, `#update_issue_state`로 제어한다.

---

## 4. 에이전트 설정

### Codex

현재 유일한 에이전트 구현체. JSON-RPC 2.0 over stdio 프로토콜을 사용한다.

```yaml
codex:
  command: codex app-server
  approval_policy: never          # 자동 승인
  thread_sandbox: locked-to-workspace
  stall_timeout_ms: 300000
```

`approval_policy: never` — 에이전트의 `item/approval/request`를 자동 수락한다. 신뢰할 수 있는 환경에서만 사용할 것.

### 동시 실행 제어

```yaml
agent:
  max_concurrent_agents: 10       # 전체 상한
  max_concurrent_agents_by_state:
    todo: 2                       # Todo 상태 이슈는 최대 2개 동시 실행
    in progress: 5                # In Progress는 최대 5개
```

전체 상한과 상태별 상한이 동시에 적용된다. 슬롯 부족 시 다음 tick까지 대기한다.

---

## 5. 워크스페이스 & 훅

### 디렉토리 구조

```
{workspace.root}/
  PRJ-123/              # sanitize된 이슈 식별자
  PRJ-124/
```

식별자의 영숫자, `_`, `-`, `.` 이외 문자는 `_`로 치환된다.

### 라이프사이클

1. **prepare** — 디렉토리 생성 (이미 존재하면 `tmp/`, `.elixir_ls/` 정리)
2. **after_create 훅** — 최초 생성 시만 실행 (예: `git init`)
3. **before_run 훅** — 에이전트 실행 직전
4. **에이전트 세션** — 워크스페이스 내에서 실행
5. **after_run 훅** — 에이전트 세션 완료 후
6. **remove** — terminal 상태 전환 시 `before_remove` 훅 → 디렉토리 삭제

### 훅 예시

```yaml
hooks:
  after_create: |
    git init
    git config user.email "agent@symphony"
    git config user.name "Symphony Agent"
  before_run: |
    git fetch origin main 2>/dev/null || true
  after_run: |
    git add -A && git commit -m "agent session complete" || true
  timeout_ms: 60000
```

훅 실패 시:
- `after_create` 실패 → 워크스페이스 삭제, 디스패치 중단
- `before_run` 실패 → 에이전트 실행 중단, 비정상 종료 처리
- `after_run`, `before_remove` 실패 → 로그 경고, 계속 진행

---

## 6. 모니터링

### 대시보드

브라우저에서 `http://localhost:{port}/` 접속. Turbo로 5초마다 자동 갱신된다.

표시 항목:
- Running / Retrying 카운트
- 총 토큰 사용량 (input / output)
- 총 실행 시간
- Rate limits (JSON)
- 실행 중 세션 테이블 (식별자, 상태 배지, 경과 시간, 마지막 이벤트)
- 재시도 큐 테이블 (식별자, 시도 횟수, 예정 시각, 에러)

### API 엔드포인트

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/v1/state` | 오케스트레이터 스냅샷 (JSON) |
| `POST` | `/api/v1/refresh` | 즉시 poll+reconcile 트리거 (202 Accepted) |
| `GET` | `/api/v1/:issue_identifier` | 특정 이슈 상세 (running/retry 상태) |

`/api/v1/state` 응답 예시:

```json
{
  "generated_at": "2026-03-13T10:00:00Z",
  "counts": { "running": 2, "retrying": 1 },
  "running": [
    {
      "issue_id": "abc-123",
      "issue_identifier": "PRJ-42",
      "state": "In Progress",
      "elapsed_seconds": 120.5,
      "last_codex_event": "turn/completed"
    }
  ],
  "retrying": [
    {
      "issue_id": "def-456",
      "issue_identifier": "PRJ-99",
      "attempt": 3,
      "due_at": "2026-03-13T10:01:00Z",
      "error": "stall_timeout"
    }
  ],
  "codex_totals": {
    "input_tokens": 15000,
    "output_tokens": 8000,
    "total_tokens": 23000,
    "seconds_running": 3600.0
  }
}
```

### 로그

Rails.logger에 구조화 태그로 출력된다.

```
[Symphony] Booting with workflow=/path/to/WORKFLOW.md
[Orchestrator] Dispatching PRJ-42 (abc-123)
[Orchestrator] Stall detected for abc-123, elapsed=310000ms
[AgentRunner] Workspace prepare failed issue=PRJ-42: ...
```

주요 태그: `issue_id=`, `issue_identifier=`, `session_id=`

---

## 7. 트러블슈팅

### Stall 감지 & 자동 종료

`codex.stall_timeout_ms` (기본 5분) 동안 에이전트 이벤트가 없으면:
1. 해당 프로세스에 `SIGTERM` 전송
2. 실행 목록에서 제거
3. exponential backoff로 재시도 스케줄링

→ `stall_timeout_ms`를 늘리거나, 에이전트가 주기적으로 이벤트를 보내는지 확인한다.

### 재시도 백오프

비정상 종료 시 exponential backoff가 적용된다.

| 시도 | 대기 시간 |
|---|---|
| 1 | 10초 |
| 2 | 20초 |
| 3 | 40초 |
| 4 | 80초 |
| 5 | 160초 |
| 6+ | 300초 (상한) |

정상 종료 시에는 1초 후 재디스패치한다 (이슈가 여전히 active 상태인 경우).

상한은 `agent.max_retry_backoff_ms`로 조정한다.

### 흔한 에러

| 증상 | 원인 | 해결 |
|---|---|---|
| `Config validation failed: tracker.api_key is required` | `$LINEAR_API_KEY` 미설정 | 환경변수 설정 |
| `Unsupported tracker kind` | `tracker.kind` 오타 | `linear` 또는 `memory`만 지원 |
| `Workflow file not found` | WORKFLOW.md 경로 오류 | 절대 경로 또는 현재 디렉토리 확인 |
| `Hook timed out` | 훅 실행이 timeout_ms 초과 | 훅 스크립트 최적화 또는 `timeout_ms` 증가 |
| `workspace_outside_root` | 식별자에 `../` 등 경로 탈출 시도 | 식별자 sanitize 확인 |
| 503 on API endpoints | 오케스트레이터 미초기화 | `bin/symphony`가 정상 부팅되었는지 확인 |
| 이슈가 디스패치되지 않음 | 슬롯 부족 또는 blocker 존재 | `/api/v1/state`로 running/retrying 수 확인, 블로커 이슈 상태 확인 |
