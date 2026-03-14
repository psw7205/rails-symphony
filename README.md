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
| Tracker | 어댑터 패턴 — Linear (1차), GitHub Issues (2차) |
| Template | Liquid (strict mode) |

## 아키텍처

SPEC의 6개 계층을 Rails 컨벤션에 매핑합니다.

```
Policy Layer        → WORKFLOW.md (repo-owned)
Configuration Layer → Workflow, ServiceConfig 모델
Coordination Layer  → PollJob, Orchestrator
Execution Layer     → AgentWorkerJob, Workspace
Integration Layer   → Trackers::Linear
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
```

### 어댑터 인터페이스

**Trackers::Base** — 이슈 조회, 상태 동기화, 터미널 상태 정리

**Agents::Base** — 세션 시작/종료, 턴 실행, 이벤트 스트리밍

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

### 2차 (인터페이스만 준비)

- Claude Code 어댑터
- GitHub Issues 어댑터
- HTTP JSON API / Turbo 대시보드

## 참고

- [OpenAI Symphony](https://github.com/openai/symphony) — 원본 프로젝트
- [Symphony SPEC](symphony/SPEC.md)
- [설계 문서](docs/plans/2026-03-05-symphony-rails-design.md)
- [Elixir 참조 구현](symphony/elixir/)

## 라이선스

[Apache License 2.0](LICENSE)
