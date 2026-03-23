# Multi-Project Admin Console Trigger and Operations Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** verified external triggers, safer recurring scheduling, and operator-facing workflow controls/triage를 추가해 멀티 프로젝트 콘솔을 "운영 가능한 control plane" 단계로 끌어올린다.

**Architecture:** 기존 `ManagedWorkflow` + `WorkflowRuntimeManager` + `Orchestrator` 구조는 유지한다. 대신 recurring poll, manual refresh, database issue write, external webhook을 공통 workflow-trigger path로 정규화하고, trigger/tick health를 DB에 남겨 UI와 운영 문서에서 같은 source of truth를 보게 한다. UI는 전면 재설계하지 않고 workflow detail/dashboard에 필요한 운영 액션과 triage 정보만 추가한다.

**Tech Stack:** Rails 8, SQLite, Solid Queue, Active Record, ERB/Turbo, existing Symphony tracker/runtime stack

---

## Base Inputs

- Current design: `docs/_archive/2026-03-19-multi-project-admin-console-design.md`
- Current implementation plan: `docs/_archive/2026-03-19-multi-project-admin-console-implementation.md`
- Tracker plans:
  - `docs/_archive/2026-03-13-tracker-database.md`
  - `docs/_archive/2026-03-13-tracker-github-issues.md`
- Operator docs:
  - `README.md`
  - `docs/guides/operator-guide.md`
  - `docs/guides/feature-reference.md`

## Current State Snapshot

- 멀티 프로젝트 admin domain, workflow-scoped runtime, dashboard/workflow screens, database tracker CRUD, github tracker read/sync, legacy import task는 landed 상태다.
- `PollJob`는 active workflow 전부에 대해 `WorkflowPollJob`를 fanout enqueue하지만, trigger source 기록, dedupe, last success/failure summary는 없다.
- workflow detail은 snapshot/capabilities/retry/run history를 보여주지만 explicit operator control surface는 없다.
- workflow refresh API는 managed mode에서 즉시 `tick`을 실행하는 synchronous path다. 반환 payload는 async queue semantics처럼 보이지만 실제 구현은 그렇지 않다.
- `ManagedIssuesController`의 database tracker write는 성공 후 redirect만 하고 즉시 runtime refresh를 트리거하지 않는다.
- 인증/권한 계층은 아직 없고, webhook endpoint/signature verification도 아직 없다.
- 2026-03-23 기준 `bin/rails test`는 295 runs, 1077 assertions, 0 failures, 0 errors, 0 skips였다.

## Evaluated Directions

### Direction A: Trigger and Operations Hardening

**Scope:** webhook trigger/signature verification, background scheduling robustness, workflow manual controls, observability/failure triage UX

**Pros**

- 현재 codebase의 가장 직접적인 운영 gap을 메운다.
- 기존 runtime manager/orchestrator 경계를 유지한 채 확장 가능하다.
- external tracker read/sync landed 상태를 바로 활용할 수 있다.
- auth나 external mutation보다 범위가 좁고, operator value가 즉시 나온다.

**Cons**

- job/runtime path가 concurrency-sensitive해서 테스트 설계가 중요하다.
- webhook idempotency와 poll fallback 조합을 명확히 설계해야 한다.
- UI 변화가 작더라도 state model이 먼저 안정화되어야 한다.

**Risks**

- poll/webhook/manual refresh 중복으로 duplicate dispatch가 발생할 수 있다.
- signature verification을 허술하게 넣으면 false positive/negative가 나온다.
- operator action semantics를 애매하게 두면 runtime state와 DB status가 어긋난다.

### Direction B: Auth/Authorization First, Then External Write Paths

**Scope:** 로그인, role/project scoping, action gating, external tracker mutation 전 준비

**Pros**

- 멀티 프로젝트 콘솔의 가장 큰 보안 공백을 줄인다.
- future external mutation과 destructive operator action의 안전한 전제조건이 된다.
- shared deployment를 염두에 둔 구조를 먼저 세울 수 있다.

**Cons**

- 현재 앱에는 auth model이 전혀 없어 architectural surface가 크다.
- single-user/self-hosted 전제의 1차 구현보다 한 단계 큰 설계 판단이 필요하다.
- external mutation을 이번에 같이 열지 않으면 즉시 운영 효익이 제한적이다.

**Risks**

- 성급한 role model이 이후 project/workflow ownership 모델을 고정해버릴 수 있다.
- console 전체 controller/view/test에 넓게 퍼져 작업이 커진다.

### Direction C: Console UX and Cutover Refinement

**Scope:** admin UI polish, IA refinement, import/cutover ergonomics, triage surfacing 일부

**Pros**

- 현재 landed 기능의 사용성은 빠르게 개선할 수 있다.
- 상대적으로 low-risk다.
- import/cutover 흐름을 운영자 입장에서 다듬기 쉽다.

**Cons**

- poll scaling, trigger latency, manual control, webhook 부재 같은 구조적 gap은 남는다.
- trigger/control contract가 고정되기 전에 UI만 다듬으면 재작업 가능성이 높다.

**Risks**

- presentation에 집중하다가 실제 운영 병목을 뒤로 미룰 수 있다.
- import UX 개선이 premature optimization이 될 수 있다.

## Recommendation

Direction A를 추천한다.

이유는 단순하다. 현재 landed scope는 "관리와 조회"까지는 충분히 올라왔지만, 운영자가 실제로 multi-workflow system을 다루는 trigger/control plane은 아직 약하다. `PollJob` fanout, synchronous refresh API, immediate triage signal 부재는 이미 코드에 드러난 제한이다. 반면 auth/authorization은 필요하지만 한 단계 더 큰 boundary decision이고, external tracker mutation은 auth/audit/control plane 없이 열면 위험하다. UI/cutover polish도 가치가 있지만 trigger/control contract 위에서 정리하는 편이 맞다.

## Success Criteria

- recurring poll, manual refresh, database tracker write, verified external webhook이 모두 같은 workflow-trigger path를 사용한다.
- invalid signature 또는 duplicate delivery는 workflow tick을 일으키지 않고 triage 가능한 기록을 남긴다.
- active workflow fanout이 blind enqueue가 아니라 workflow-level dedupe/health summary를 가진다.
- operator가 workflow detail에서 `pause`, `resume`, `refresh now`를 실행할 수 있다.
- dashboard/workflow detail에서 last trigger source/time/result, last tick failure, recent trigger failures를 볼 수 있다.
- poll fallback은 유지되지만 webhook-capable workflow의 trigger provenance를 구분할 수 있다.
- docs가 webhook secret config, control semantics, triage flow를 반영한다.

## Out of Scope

- 사용자 인증/권한 모델
- external tracker mutation (`linear`/`github` state/comment/create/update)
- broad visual redesign or brand-level UI overhaul
- import task를 wizard화하거나 multi-step cutover assistant로 확장하는 일
- running agent session에 대한 force-stop/kill UX 공개
- Slack/Email notifications

## Excluded Candidates and Why

- **Auth / authorization:** 중요하지만 현재 코드에 identity/ownership 기반이 전혀 없다. trigger/control semantics를 먼저 안정화한 뒤, 그 액션을 누가 실행할 수 있는지 얹는 편이 더 안전하다.
- **External tracker mutation range:** read/sync만 landed 된 상태에서 곧바로 write를 열면 audit/permission/retry policy까지 같이 풀어야 한다. 이번 단계의 natural next step이 아니다.
- **Import/cutover ergonomics:** import task와 docs sync는 이미 landed이고 full suite green이다. 운영 trigger path가 안정화된 뒤 UX 개선을 다시 보는 편이 합리적이다.
- **Broad admin UI polish / IA rewrite:** 이번 단계에서는 triage와 controls를 수용하는 최소 refinement만 한다. 구조 재배치는 ops state model이 고정된 뒤에 한다.
- **Hard stop/manual retry-all controls:** 현재 `request_worker_stop`는 내부 runtime helper 성격이 강하다. 이를 operator-facing action으로 노출하려면 별도 safety contract가 필요하므로 이번 계획에서 제외한다.

## Chunk 1: Workflow Trigger Ledger and Async Refresh Contract

### Task 1: workflow trigger event ledger와 tick health summary 추가

**Files:**
- Create: `db/migrate/<timestamp>_create_symphony_workflow_trigger_events.rb`
- Create: `app/models/symphony/workflow_trigger_event.rb`
- Modify: `db/migrate/<timestamp>_scope_runtime_tables_to_managed_workflows.rb` only if schema extension cannot fit cleanly in a new migration
- Create: `db/migrate/<timestamp>_add_trigger_health_to_symphony_orchestrator_states.rb`
- Modify: `app/models/symphony/orchestrator_state.rb`
- Create: `test/models/symphony/workflow_trigger_event_test.rb`
- Modify: `test/models/symphony/orchestrator_state_test.rb`

**Data model decisions:**
- `WorkflowTriggerEvent` is append-only audit for trigger requests.
- Minimal columns:
  - `managed_workflow_id`
  - `source` (`poll`, `manual_refresh`, `database_write`, `webhook_github`, `webhook_linear`)
  - `provider`
  - `delivery_id`
  - `status` (`accepted`, `ignored_duplicate`, `rejected_signature`, `enqueued`, `running`, `succeeded`, `failed`)
  - `signature_state`
  - `requested_at`, `started_at`, `finished_at`
  - `error`
  - `metadata` JSON
- `OrchestratorState` keeps summary fields only:
  - `last_trigger_source`
  - `last_triggered_at`
  - `last_tick_started_at`
  - `last_tick_finished_at`
  - `last_tick_status`
  - `last_tick_error`
  - optional `last_workflow_trigger_event_id`

### Steps

- [x] Add failing model tests for event status validation, workflow association, and duplicate delivery handling.
- [x] Add migration for `symphony_workflow_trigger_events` with indexes on `managed_workflow_id`, `status`, and provider delivery keys.
- [x] Add migration extending `symphony_orchestrator_states` with last-trigger / last-tick summary fields.
- [x] Implement `WorkflowTriggerEvent` scopes for recent failures, recent accepted, and unresolved failures.
- [x] Keep detailed audit in `WorkflowTriggerEvent`; do not turn `OrchestratorState` into an event log.

Run: `bin/rails test test/models/symphony/workflow_trigger_event_test.rb test/models/symphony/orchestrator_state_test.rb`
Expected: PASS

### Task 2: workflow-trigger scheduler로 poll/manual/database write를 공통 enqueue path로 정규화

**Files:**
- Create: `app/models/symphony/workflow_trigger_scheduler.rb`
- Modify: `app/jobs/symphony/poll_job.rb`
- Modify: `app/jobs/symphony/workflow_poll_job.rb`
- Modify: `app/controllers/api/v1/refreshes_controller.rb`
- Modify: `app/controllers/symphony/managed_issues_controller.rb`
- Create: `test/models/symphony/workflow_trigger_scheduler_test.rb`
- Modify: `test/jobs/symphony/poll_job_test.rb`
- Modify: `test/jobs/symphony/workflow_poll_job_test.rb`
- Modify: `test/controllers/api/v1/refreshes_controller_test.rb`
- Modify: `test/controllers/symphony/managed_issues_controller_test.rb`

**Contract decisions:**
- `PollJob` no longer calls `WorkflowPollJob.perform_later` directly.
- manual refresh API no longer runs `tick` synchronously in the request thread.
- database tracker create/update/destroy enqueues immediate workflow refresh through the same scheduler.
- scheduler is responsible for dedupe and audit record creation; `WorkflowPollJob` is responsible for execution and final status update.

### Steps

- [x] Add failing tests that recurring poll uses scheduler and records one accepted trigger per workflow.
- [x] Add failing tests that workflow refresh API returns `202` for a real queued operation instead of synchronous execution.
- [x] Add failing tests that `ManagedIssuesController` write success enqueues a `database_write` trigger for the owning workflow.
- [x] Implement `WorkflowTriggerScheduler.enqueue(workflow_id:, source:, delivery_id: nil, metadata: {})`.
- [x] Dedupe exact duplicate webhook deliveries by provider + delivery id, and dedupe overlapping non-webhook refresh requests by workflow while one accepted/running trigger is still open.
- [x] Update `WorkflowPollJob` to accept trigger context, mark event `running`, execute `orchestrator.tick`, then persist `succeeded` or `failed` summary back to both `WorkflowTriggerEvent` and `OrchestratorState`.
- [x] Preserve legacy file-mode poll path. Managed-mode changes must not break `Symphony.orchestrator` fallback behavior.

Run: `bin/rails test test/models/symphony/workflow_trigger_scheduler_test.rb test/jobs/symphony/poll_job_test.rb test/jobs/symphony/workflow_poll_job_test.rb test/controllers/api/v1/refreshes_controller_test.rb test/controllers/symphony/managed_issues_controller_test.rb`
Expected: PASS

## Chunk 2: Verified External Webhook Ingestion

### Task 3: GitHub/Linear webhook endpoint와 signature verification 추가

**Files:**
- Create: `app/controllers/symphony/webhooks/github_controller.rb`
- Create: `app/controllers/symphony/webhooks/linear_controller.rb`
- Create: `app/models/symphony/webhook_signature_verifier.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/symphony/webhooks/github_controller_test.rb`
- Create: `test/controllers/symphony/webhooks/linear_controller_test.rb`
- Create: `test/models/symphony/webhook_signature_verifier_test.rb`

**Assumptions to confirm before implementation:**
- exact provider signature headers and payload fields must be locked from official docs/examples before coding tests
- webhook secret is stored in `TrackerConnection.config` as env-var reference or opaque string, consistent with current connection secret handling

### Steps

- [x] Add failing request tests for valid signature, invalid signature, missing signature, and duplicate delivery id cases for both providers.
- [x] Implement provider-aware signature verifier without adding a new secret store.
- [x] Add routes under a dedicated namespace such as `/webhooks/github` and `/webhooks/linear`.
- [x] Reject invalid signature with `401` or `403`; do not enqueue work and do not mutate workflow health as success.
- [x] Persist a `WorkflowTriggerEvent` row for accepted and rejected webhook deliveries so operators can distinguish auth failure from runtime failure.
- [x] Keep request-thread work minimal: verify, resolve workflows, enqueue, return.

Run: `bin/rails test test/models/symphony/webhook_signature_verifier_test.rb test/controllers/symphony/webhooks/github_controller_test.rb test/controllers/symphony/webhooks/linear_controller_test.rb`
Expected: PASS

### Task 4: provider event routing과 workflow resolution을 DB-managed model에 맞게 고정

**Files:**
- Create: `app/models/symphony/workflow_webhook_router.rb`
- Modify: `app/models/symphony/tracker_connection.rb` only if connection-level helpers improve clarity
- Create: `test/models/symphony/workflow_webhook_router_test.rb`

**Routing rules:**
- resolve only active `ManagedWorkflow`
- match by `tracker_connection.kind` and provider-specific config identity
- one delivery may fan out to multiple workflows if they intentionally share the same connection/config
- ignore unsupported provider event types/actions without raising

### Steps

- [x] Add failing tests for GitHub repo match, Linear project match, inactive workflow exclusion, and multi-workflow fanout on shared connection.
- [x] Implement routing in a dedicated object; do not embed provider-specific matching in controllers.
- [x] Record ignored events as audit rows with `status: ignored_duplicate` or other explicit non-success status, not silent drops.
- [x] Ensure webhook acceptance path reuses `WorkflowTriggerScheduler` instead of calling `WorkflowRuntimeManager` or `Orchestrator` directly.

Run: `bin/rails test test/models/symphony/workflow_webhook_router_test.rb`
Expected: PASS

## Chunk 3: Operator Controls and Failure Triage UX

### Task 5: workflow detail에 explicit operator controls 추가

**Files:**
- Create: `app/controllers/symphony/workflow_operations_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/symphony/workflows_controller.rb`
- Modify: `app/views/symphony/workflows/show.html.erb`
- Create: `test/controllers/symphony/workflow_operations_controller_test.rb`
- Modify: `test/controllers/symphony/workflows_controller_test.rb`

**Control scope for this plan:**
- `refresh_now`
- `pause`
- `resume`

**Control semantics:**
- `pause`: mark workflow inactive and remove it from recurring poll/webhook eligibility for future triggers
- `resume`: mark workflow active and enqueue an immediate refresh
- `refresh_now`: enqueue a manual refresh only for active workflows

### Steps

- [x] Add failing controller tests for pause/resume/refresh actions and invalid transitions.
- [x] Expose operator actions as dedicated POST routes, not overloaded edit/update flows.
- [x] Show control availability and disabled states on workflow detail.
- [x] Reflect paused workflows cleanly in dashboard counts and workflow detail copy.
- [x] Do not expose hard-stop or kill-session controls in this plan.

Run: `bin/rails test test/controllers/symphony/workflow_operations_controller_test.rb test/controllers/symphony/workflows_controller_test.rb`
Expected: PASS

### Task 6: dashboard/workflow triage 정보를 trigger-health 기준으로 재구성

**Files:**
- Modify: `app/models/symphony/console_snapshot.rb`
- Modify: `app/controllers/symphony/dashboard_controller.rb`
- Modify: `app/controllers/symphony/workflows_controller.rb`
- Modify: `app/views/symphony/dashboard/show.html.erb`
- Modify: `app/views/symphony/workflows/show.html.erb`
- Modify: `app/assets/stylesheets/symphony/dashboard.css`
- Modify: `app/controllers/api/v1/issues_controller.rb`
- Modify: `test/controllers/symphony/dashboard_controller_test.rb`
- Modify: `test/controllers/symphony/workflows_controller_test.rb`
- Modify: `test/controllers/api/v1/issues_controller_test.rb`

**UX target:**
- dashboard row마다 last trigger source/time/status
- workflow detail에 recent trigger events table
- tick failure, signature failure, retry backlog를 구분해 보이기
- issue JSON에 last_error/trigger summary를 조금 더 실제 값으로 채우기

### Steps

- [x] Add failing view/controller tests for last trigger metadata and recent trigger failures rendering.
- [x] Extend `ConsoleSnapshot` to aggregate trigger/tick health without rebuilding runtime state from UI code.
- [x] Add recent trigger events table to workflow detail; cap row count to a bounded recent window.
- [x] Update issue JSON so `recent_events` and `tracked` stop being empty placeholders when trigger/tick metadata exists.
- [x] Keep IA changes minimal and functional; avoid broad page re-layout unrelated to new operator signals.

Run: `bin/rails test test/controllers/symphony/dashboard_controller_test.rb test/controllers/symphony/workflows_controller_test.rb test/controllers/api/v1/issues_controller_test.rb`
Expected: PASS

## Chunk 4: Docs and Verification

### Task 7: operator docs를 trigger/control/triage model에 맞춰 동기화

**Files:**
- Modify: `README.md`
- Modify: `docs/guides/operator-guide.md`
- Modify: `docs/guides/feature-reference.md`
- Modify: `docs/_archive/2026-03-19-multi-project-admin-console-design.md` only if follow-up notes need narrowing

### Steps

- [x] Document new webhook endpoints, supported providers, secret config location, and signature failure behavior.
- [x] Document recurring poll as fallback rather than sole trigger path.
- [x] Document pause/resume/refresh semantics and what they do not do.
- [x] Document triage flow: webhook rejected vs trigger accepted but tick failed vs issue retry backlog.
- [x] Keep auth and external mutation explicitly called out as future work.

Run: `bin/rails test`
Expected: PASS

### Task 8: integration coverage와 full verification

**Files:**
- Create: `test/integration/symphony/workflow_triggering_integration_test.rb`
- Modify: existing managed runtime integration tests only as needed for new async trigger contract

### Steps

- [x] Add integration test: valid webhook -> workflow trigger accepted -> `WorkflowPollJob` executes -> dashboard/workflow detail reflect trigger success.
- [x] Add integration test: invalid signature -> no job enqueue -> workflow detail shows rejected trigger event.
- [x] Add integration test: paused workflow ignores recurring poll/webhook-triggered execution.
- [x] Run targeted suites for models, jobs, controllers, and integration slices added by this plan.
- [x] Run full suite: `bin/rails test`.

Run: `bin/rails test`
Expected: PASS

## Test and Verification Matrix

- Trigger ledger/model:
  - `bin/rails test test/models/symphony/workflow_trigger_event_test.rb test/models/symphony/workflow_trigger_scheduler_test.rb test/models/symphony/orchestrator_state_test.rb`
- Scheduling/jobs:
  - `bin/rails test test/jobs/symphony/poll_job_test.rb test/jobs/symphony/workflow_poll_job_test.rb`
- Webhooks:
  - `bin/rails test test/models/symphony/webhook_signature_verifier_test.rb test/models/symphony/workflow_webhook_router_test.rb test/controllers/symphony/webhooks/github_controller_test.rb test/controllers/symphony/webhooks/linear_controller_test.rb`
- Operator controls/UI:
  - `bin/rails test test/controllers/symphony/workflow_operations_controller_test.rb test/controllers/symphony/workflows_controller_test.rb test/controllers/symphony/dashboard_controller_test.rb test/controllers/api/v1/issues_controller_test.rb test/controllers/api/v1/refreshes_controller_test.rb`
- Integration:
  - `bin/rails test test/integration/symphony/workflow_triggering_integration_test.rb test/integration/symphony/workflow_scoped_runtime_integration_test.rb`
- Final gate:
  - `bin/rails test`

## Implementation Notes

- 가장 중요한 correctness point는 duplicate trigger suppression과 workflow-local isolation이다. 하나의 webhook delivery나 manual refresh가 cross-workflow dispatch를 일으키면 안 된다.
- `WorkflowRuntimeManager` cache는 여전히 optimization일 뿐이다. webhook/controller/job path는 cache miss에서도 동작해야 한다.
- webhook acceptance는 HTTP request 안에서 orchestrator를 직접 호출하지 않는다. verify + route + enqueue만 한다.
- summary state와 event ledger를 섞지 않는다. 화면은 summary를 기본으로 보고, triage drill-down은 event ledger를 본다.
- provider payload field names는 구현 전에 공식 문서 기반 fixture로 테스트에 먼저 고정한다. 추정으로 coding하지 않는다.
