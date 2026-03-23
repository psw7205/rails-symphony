# Rails Symphony

[OpenAI Symphony](https://github.com/openai/symphony) SPEC 기반의 Rails 구현체.
이슈 트래커를 모니터링하고 코딩 에이전트를 자율적으로 디스패치하여, 엔지니어가 에이전트를 감독하는 대신 **작업 자체를 관리**할 수 있게 합니다.

> [!WARNING]
> 초기 개발 단계입니다. 신뢰할 수 있는 환경에서만 사용하세요.

## 스택

| 항목 | 선택 |
|------|------|
| Framework | Rails 8 + SQLite |
| Background Job | Solid Queue |
| Agent | 어댑터 패턴 — Codex (1차), Claude Code (2차) |
| Tracker | 어댑터 패턴 — Linear, Database, GitHub Issues |
| Template | Liquid (strict mode) |

## 아키텍처

SPEC의 6개 계층을 Rails 컨벤션에 매핑합니다.

```
Policy Layer        → WORKFLOW.md 또는 DB-managed prompt template
Configuration Layer → Workflow/WorkflowStore, ManagedWorkflow/ManagedWorkflowStore, ServiceConfig
Coordination Layer  → PollJob, WorkflowPollJob, Orchestrator, WorkflowRuntimeManager
Execution Layer     → AgentWorkerJob, Workspace
Integration Layer   → Trackers::Linear, Trackers::Database, Trackers::GithubIssues
Observability Layer → Rails.logger + structured tags
```

### 핵심 흐름

```
PollJob (Solid Queue recurring)
  → Orchestrator.tick
    → reconcile: stall 감지, 트래커 상태 동기화
    → fetch: 후보 이슈 조회
    → dispatch: 우선순위 정렬 → AgentWorkerJob 큐잉

AgentWorkerJob
  → Workspace 준비 (sanitize, hooks)
  → Agent 세션 시작 (JSON-RPC stdio)
  → Turn loop (prompt → 실행 → 이벤트 → 상태 확인)
  → 결과 보고 → 재시도 또는 완료

Managed Admin Console
  → ManagedProject / ManagedWorkflow / connection CRUD
  → WorkflowRuntimeManager.fetch(workflow_id)
  → workflow-scoped snapshot / refresh / issues UI
```

### 어댑터 인터페이스

**Trackers::Base** — 이슈 조회, 상태 동기화, 터미널 상태 정리

**Agents::Base** — 세션 시작/종료, 턴 실행, 이벤트 스트리밍

## 셋업

```bash
bin/setup --skip-server   # 의존성 설치 + DB 준비
```

현재는 두 가지 운영 모드를 지원합니다.

- legacy file mode: `WORKFLOW.md`를 직접 읽어 `bin/symphony`로 기동
- managed DB mode: Rails 앱의 admin console에서 project/workflow를 관리하고 workflow-scoped runtime을 on-demand로 구성

## 실행

### Legacy File Mode

```bash
bin/symphony [WORKFLOW.md 경로] [--logs-root DIR] [--port PORT]
```

- `WORKFLOW.md` 경로 생략 시 현재 디렉토리의 `WORKFLOW.md`를 자동 탐색
- `--port` 미지정 시 `WORKFLOW.md`의 `server.port`를 사용하고, 둘 다 없으면 Rails 기본 포트를 사용
- `Symphony.boot!`가 호출되어 오케스트레이터/파일 감시/폴링 루프를 함께 기동

### Managed DB Mode

```bash
bin/rails server
bin/jobs
```

- root dashboard (`/`)가 멀티 프로젝트 admin console entrypoint다
- runtime은 `WorkflowRuntimeManager`가 workflow 단위로 조립/캐시한다
- background poll/dispatch는 Rails app + Solid Queue worker(`bin/jobs`) 조합을 전제로 한다
- recurring poll, workflow refresh, database tracker write, verified webhook은 `WorkflowTriggerScheduler`를 통해 같은 workflow-trigger path를 사용한다
- workflow detail에서 `refresh now`, `pause`, `resume` control과 recent trigger ledger를 볼 수 있다
- webhook endpoint는 `/webhooks/github`, `/webhooks/linear` 이며 secret은 tracker connection config의 `tracker.webhook_secret`에 plain string 또는 `"$ENV_VAR"` 형태로 둔다

### Legacy `WORKFLOW.md` Import

기존 file mode 설정을 DB-managed mode로 옮길 때는 import task를 사용한다.

```bash
bin/rails "symphony:import_workflow[/absolute/path/to/WORKFLOW.md,Project Name,Workflow Name]"
```

- `project_name`, `workflow_name`은 선택 사항이다
- 생략하면 `WORKFLOW.md`가 들어 있는 디렉토리명을 기반으로 이름/slug를 만든다
- tracker credential은 해석된 평문 값이 아니라 `"$ENV_VAR"` reference 문자열 그대로 저장한다

## WORKFLOW.md 구조

YAML front matter + Liquid 템플릿 본문으로 구성된 단일 파일 설정.

**YAML front matter** — tracker, workspace, agent, codex, polling 설정을 정의.
**본문** — Liquid 템플릿으로 `{{ issue.identifier }}`, `{{ issue.title }}` 등 이슈 변수를 바인딩하여 에이전트 프롬프트를 생성.

참고 예시: `https://github.com/openai/symphony/blob/main/elixir/WORKFLOW.md`

## 테스트

```bash
bin/rails test
```

`webmock` + `Trackers::Memory` 어댑터로 외부 의존성 없이 테스트 가능.

## 구현 범위

### 1차 (Core Conformance, SPEC 18.1)

- WORKFLOW.md 로더 — YAML front matter + Liquid prompt
- Config 레이어 — typed getters, `$VAR`/`~` 확장
- WORKFLOW.md 동적 리로드
- Orchestrator — poll, dispatch, reconciliation, state machine
- Linear 트래커 — GraphQL 기반
- Workspace 매니저 — sanitize, hooks, safety invariants
- Codex JSON-RPC stdio 클라이언트
- 재시도 큐 — exponential backoff + continuation retry
- 구조화 로그
- CLI — `bin/symphony WORKFLOW.md`

### 2차 (부분 구현)

- Claude Code 어댑터
- GitHub Issues 어댑터
- HTTP JSON API (`/api/v1/state`, `/api/v1/refresh`, `/api/v1/:issue_identifier`)
- Turbo 대시보드 루트 페이지 (`/`)
- 멀티 프로젝트 admin console (`ManagedProject`, `ManagedWorkflow`, DB-backed connections/issues)
- workflow trigger ledger + async workflow refresh contract
- verified GitHub/Linear webhook ingestion
- workflow pause/resume/refresh controls + trigger/tick triage UI

## 참고

- [운영 가이드](docs/guides/operator-guide.md) — 설정, 실행, 모니터링, 트러블슈팅
- [기능 동작 레퍼런스](docs/guides/feature-reference.md) — 내부 동작 흐름, 상태 머신, 어댑터 확장
- [멀티 프로젝트 어드민 콘솔 설계](docs/plans/2026-03-19-multi-project-admin-console-design.md)
- [멀티 프로젝트 어드민 콘솔 구현 계획](docs/plans/2026-03-19-multi-project-admin-console-implementation.md)
- [OpenAI Symphony](https://github.com/openai/symphony) — 원본 프로젝트
- [Symphony SPEC](https://github.com/openai/symphony/blob/main/SPEC.md)
- [설계 문서](docs/plans/2026-03-05-symphony-rails-design.md)
- [Elixir 참조 구현](https://github.com/openai/symphony/tree/main/elixir)

## 라이선스

[Apache License 2.0](LICENSE)
