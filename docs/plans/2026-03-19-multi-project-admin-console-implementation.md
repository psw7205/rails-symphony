# Multi-Project Admin Console Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DB-backed 멀티 프로젝트 어드민 콘솔과 workflow-scoped runtime을 도입해 여러 project/workflow를 한 Rails 앱에서 운영한다.

**Architecture:** 기존 `Symphony::Orchestrator` 핵심 로직은 유지하되, 모든 runtime 객체를 `ManagedWorkflow` 단위로 스코프한다. 운영 설정과 prompt template은 DB 관리 도메인에서 소유하고, runtime persistence도 workflow별로 분리해 web/job process 어디서든 동일한 workflow context를 재구성할 수 있게 한다. UI는 tracker kind 하드코딩 대신 capability 기반으로 동작을 분기하고, 전역 콘솔은 workflow별 snapshot을 집계해서 표시한다.

**Tech Stack:** Rails 8, SQLite, Solid Queue, Active Record, ERB, 기존 Symphony tracker/agent adapter

---

## Base Inputs

- Base design: `docs/plans/2026-03-19-multi-project-admin-console-design.md`
- Related tracker plans:
  - `docs/plans/2026-03-13-tracker-database.md`
  - `docs/plans/2026-03-13-tracker-github-issues.md`

## Locked Decisions

- `Symphony::Workflow`는 이미 `WORKFLOW.md` parser이므로 관리용 AR 모델 이름으로 재사용하지 않는다.
- 관리용 엔티티는 `ManagedProject`, `ManagedWorkflow`, `TrackerConnection`, `AgentConnection`, `ManagedIssue`로 둔다.
- `symphony_issues`는 runtime cache/bookkeeping으로 유지하고, `database` tracker 원장은 별도 `symphony_managed_issues` 테이블로 분리한다.
- runtime persistence는 전부 `managed_workflow_id` 기준으로 스코프한다.
- `symphony_issues.id` string PK는 당장 유지하고, workflow 간 충돌을 피하기 위해 `source_issue_id`를 별도 저장한다.
- credential은 v1에서 DB encrypted secret store를 도입하지 않고 env var reference 또는 opaque string만 저장한다.
- v1 범위는 `linear` 조회/동기화, `database` full CRUD, poll trigger, 무인증 단일 사용자 콘솔까지다.
- `github` tracker는 capability plumbing 이후 별도 plan (`2026-03-13-tracker-github-issues.md`)에 따라 붙인다.

## Success Criteria

- 여러 project/workflow를 UI와 DB에서 생성, 수정, 비활성화할 수 있다.
- 각 workflow는 tracker/agent 연결과 prompt template, runtime 설정을 DB에서 가진다.
- runtime snapshot, retry 상태, token usage, 최근 run history가 workflow 단위로 분리되어 보인다.
- 모든 job/controller가 `managed_workflow_id`만으로 runtime context를 재구성할 수 있다.
- tracker capability에 따라 issue 화면이 읽기 전용 또는 편집 가능으로 분기된다.
- 기존 단일-workflow boot path는 즉시 삭제하지 않고 호환 모드로 남긴다.

## Out of Scope for This Plan

- 외부 tracker mutation (`linear`/`github` 상태 변경, 코멘트 작성)
- webhook 수신 및 signature verification
- 사용자 인증/권한 모델
- 다중 프로세스 간 live in-memory runtime 공유

## Delivery Order

1. 관리 도메인과 runtime persistence 경계를 먼저 고정한다.
2. DB record -> `ServiceConfig` 변환 경로를 만든다.
3. workflow-scoped runtime factory/manager로 전역 singleton 의존을 걷어낸다.
4. admin read UI를 먼저 붙이고, 그 다음 CRUD를 붙인다.
5. `database` tracker와 capability 기반 UI를 연결한다.
6. docs/cutover를 마무리한다.

## Chunk 1: Admin Domain and Persistence Boundaries

### Task 1: 관리용 스키마와 AR 모델 추가

**Files:**
- Create: `db/migrate/<timestamp>_create_symphony_managed_projects.rb`
- Create: `db/migrate/<timestamp>_create_symphony_tracker_connections.rb`
- Create: `db/migrate/<timestamp>_create_symphony_agent_connections.rb`
- Create: `db/migrate/<timestamp>_create_symphony_managed_workflows.rb`
- Create: `db/migrate/<timestamp>_create_symphony_managed_issues.rb`
- Create: `app/models/symphony/managed_project.rb`
- Create: `app/models/symphony/tracker_connection.rb`
- Create: `app/models/symphony/agent_connection.rb`
- Create: `app/models/symphony/managed_workflow.rb`
- Create: `app/models/symphony/managed_issue.rb`
- Create: `test/models/symphony/managed_project_test.rb`
- Create: `test/models/symphony/tracker_connection_test.rb`
- Create: `test/models/symphony/agent_connection_test.rb`
- Create: `test/models/symphony/managed_workflow_test.rb`
- Create: `test/models/symphony/managed_issue_test.rb`

**Data shape:**
- `ManagedProject`: `name`, `slug`, `status`, `description`
- `TrackerConnection`: `name`, `kind`, `status`, `config` JSON
- `AgentConnection`: `name`, `kind`, `status`, `config` JSON
- `ManagedWorkflow`: `managed_project_id`, `tracker_connection_id`, `agent_connection_id`, `name`, `slug`, `status`, `prompt_template`, `runtime_config` JSON
- `ManagedIssue`: `managed_workflow_id`, `identifier`, `title`, `description`, `priority`, `state`, `labels` JSON, `blocked_by` JSON, `metadata` JSON

### Steps

- [ ] 모델 테스트 작성: association, slug uniqueness, `status` inclusion, required foreign keys 검증
- [ ] migration 작성: 각 테이블과 필요한 unique index 추가
- [ ] `ManagedProject has_many :managed_workflows`
- [ ] `ManagedWorkflow belongs_to :managed_project`, `belongs_to :tracker_connection`, `belongs_to :agent_connection`, `has_many :managed_issues`
- [ ] `ManagedIssue`는 `database` tracker 전용 원장임을 모델 주석과 validation으로 명시
- [ ] `config`/`runtime_config` JSON column accessor는 처음엔 단순 hash로 두고, 조기 추상화는 피한다

Run: `bin/rails test test/models/symphony/managed_project_test.rb test/models/symphony/managed_workflow_test.rb test/models/symphony/managed_issue_test.rb`
Expected: PASS

### Task 2: 기존 runtime persistence를 workflow-scoped로 변경

**Files:**
- Create: `db/migrate/<timestamp>_scope_runtime_tables_to_managed_workflows.rb`
- Modify: `app/models/symphony/persisted_issue.rb`
- Modify: `app/models/symphony/run_attempt.rb`
- Modify: `app/models/symphony/retry_entry.rb`
- Modify: `app/models/symphony/orchestrator_state.rb`
- Create: `test/models/symphony/persisted_issue_test.rb`
- Modify: `db/schema.rb`

**Required schema changes:**
- `symphony_issues`: `managed_workflow_id`, `source_issue_id`, `tracker_kind`
- `symphony_run_attempts`: `managed_workflow_id`
- `symphony_retry_entries`: `managed_workflow_id`
- `symphony_orchestrator_states`: `managed_workflow_id`

### Steps

- [ ] 실패 테스트 작성: 동일 `source_issue_id`가 서로 다른 workflow에 저장될 수 있고, 같은 workflow 안에서는 중복되면 안 되는지 검증
- [ ] migration 작성: 각 runtime 테이블에 `managed_workflow_id` 추가 및 index/foreign key 추가
- [ ] `PersistedIssue`에 `belongs_to :managed_workflow` 추가, unique index를 `[managed_workflow_id, source_issue_id]`로 둔다
- [ ] `RunAttempt`, `RetryEntry`, `OrchestratorState`도 `managed_workflow_id` association 추가
- [ ] `OrchestratorState.current`는 singleton이 아니라 `for_workflow!(managed_workflow_id)` 스타일 API로 교체
- [ ] 기존 global query helper가 있으면 workflow scope를 강제하도록 수정

Run: `bin/rails test test/models/symphony/persisted_issue_test.rb`
Expected: PASS

## Chunk 2: DB Configuration Source and Workflow Store Abstraction

### Task 3: DB record를 `ServiceConfig` 입력으로 변환하는 builder 추가

**Files:**
- Create: `app/models/symphony/workflow_config_builder.rb`
- Create: `app/models/symphony/managed_workflow_store.rb`
- Create: `test/models/symphony/workflow_config_builder_test.rb`
- Create: `test/models/symphony/managed_workflow_store_test.rb`
- Modify: `app/models/symphony/service_config.rb`

**Builder contract:**
- input: `ManagedWorkflow`, `TrackerConnection`, `AgentConnection`
- output: 기존 `ServiceConfig`가 읽을 수 있는 hash 구조
- responsibility:
  - tracker config merge
  - agent config merge
  - workflow runtime overrides merge
  - `prompt_template` 전달

### Steps

- [ ] 실패 테스트 작성: `ManagedWorkflow` + connection record 조합으로 `tracker.kind`, `workspace.root`, `agent.max_concurrent_agents`, `codex.command` 등을 읽을 수 있는지 검증
- [ ] `WorkflowConfigBuilder` 구현: DB 필드를 기존 `WORKFLOW.md` front matter shape로 정규화
- [ ] `ManagedWorkflowStore` 구현: `service_config`, `prompt_template`, `reload_if_changed!`, `last_error` 제공
- [ ] `ServiceConfig` validation을 `linear`, `database`, 향후 `github` kind까지 수용하도록 정리
- [ ] file-backed `WorkflowStore`는 그대로 두고, `ManagedWorkflowStore`와 같은 public interface를 맞춘다

Run: `bin/rails test test/models/symphony/workflow_config_builder_test.rb test/models/symphony/managed_workflow_store_test.rb test/models/symphony/service_config_test.rb`
Expected: PASS

### Task 4: legacy file workflow와 DB workflow 공존 경계 명확화

**Files:**
- Modify: `app/models/symphony/workflow_store.rb`
- Modify: `app/models/symphony/workflow.rb`
- Modify: `app/models/symphony.rb`
- Create: `test/models/symphony_test.rb`

### Steps

- [ ] 실패 테스트 작성: 기존 `Symphony.boot!(workflow_path:)`가 계속 작동하는지 검증
- [ ] `Symphony.boot!`는 legacy boot path로 남기고, DB path는 별도 entrypoint (`boot_managed!` 또는 runtime factory 경유)로 분리
- [ ] `Symphony::Workflow` parser는 이름 유지, 관리용 모델과 섞이지 않게 호출 지점을 명확히 정리
- [ ] global accessor 추가가 필요하면 legacy mode 전용인지 주석으로 분명히 남긴다

Run: `bin/rails test test/models/symphony_test.rb`
Expected: PASS

## Chunk 3: Workflow-Scoped Runtime Construction

### Task 5: process-local runtime cache와 DB 복원 가능한 runtime factory 추가

**Files:**
- Create: `app/models/symphony/runtime_context.rb`
- Create: `app/models/symphony/workflow_runtime_factory.rb`
- Create: `app/models/symphony/workflow_runtime_manager.rb`
- Create: `test/models/symphony/workflow_runtime_factory_test.rb`
- Create: `test/models/symphony/workflow_runtime_manager_test.rb`
- Modify: `app/models/symphony/orchestrator.rb`
- Modify: `app/models/symphony/orchestrator/persistable.rb`

**Required behavior:**
- factory는 `managed_workflow_id`로 tracker/workspace/agent/store/orchestrator를 조립
- manager는 process-local cache를 가질 수 있지만, miss 시 DB에서 재구성 가능해야 한다
- orchestrator persistence는 모든 write/read에 `managed_workflow_id`를 포함해야 한다

### Steps

- [ ] 실패 테스트 작성: `managed_workflow_id` 하나로 runtime context를 만들고 `snapshot` 호출이 가능한지 검증
- [ ] `RuntimeContext` 구현: `managed_workflow`, `tracker`, `workspace`, `agent`, `workflow_store`, `orchestrator`를 묶는다
- [ ] `WorkflowRuntimeFactory` 구현: active workflow record를 읽어 runtime 구성
- [ ] `WorkflowRuntimeManager` 구현: `fetch(workflow_id)`, `refresh(workflow_id)`, `snapshot(workflow_id)`, `global_snapshot`
- [ ] `Orchestrator` 초기화 시 `managed_workflow_id`를 받게 하고 persistence helper가 항상 scope를 사용하도록 변경
- [ ] `restore_from_db!`는 해당 workflow의 retry/totals만 복원하게 제한

Run: `bin/rails test test/models/symphony/workflow_runtime_factory_test.rb test/models/symphony/workflow_runtime_manager_test.rb test/models/symphony/orchestrator_snapshot_test.rb`
Expected: PASS

### Task 6: job와 API를 workflow-aware로 변경

**Files:**
- Modify: `app/jobs/symphony/agent_worker_job.rb`
- Modify: `app/jobs/symphony/poll_job.rb`
- Create: `app/jobs/symphony/workflow_poll_job.rb`
- Modify: `app/controllers/api/v1/states_controller.rb`
- Modify: `app/controllers/api/v1/refreshes_controller.rb`
- Modify: `app/controllers/api/v1/issues_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/jobs/symphony/workflow_poll_job_test.rb`
- Modify: `test/controllers/api/v1/states_controller_test.rb`
- Modify: `test/controllers/api/v1/refreshes_controller_test.rb`
- Modify: `test/controllers/api/v1/issues_controller_test.rb`

**Route direction:**
- 기존 root/dashboard route는 유지
- workflow-scoped API는 `/api/v1/workflows/:workflow_id/state`, `/refresh`, `/issues/:issue_identifier` 형태로 확장

### Steps

- [ ] 실패 테스트 작성: API가 `workflow_id` 없는 global singleton 대신 workflow-scoped runtime을 찾는지 검증
- [ ] `AgentWorkerJob` 인자에 `managed_workflow_id` 추가
- [ ] job 시작 시 runtime manager/factory로 context를 복원하고 `AgentRunner`를 구성
- [ ] `PollJob`는 legacy wrapper로 남기고, managed mode는 `WorkflowPollJob.perform_later(workflow_id:)`를 사용
- [ ] API controller는 `managed_workflow_id` 기준 snapshot을 조회하고 workspace path도 workflow-scoped로 계산

Run: `bin/rails test test/controllers/api/v1/states_controller_test.rb test/controllers/api/v1/refreshes_controller_test.rb test/controllers/api/v1/issues_controller_test.rb test/jobs/symphony/workflow_poll_job_test.rb`
Expected: PASS

## Chunk 4: Admin Read UI

### Task 7: 전역 콘솔 snapshot 집계 서비스와 메인 대시보드 개편

**Files:**
- Create: `app/models/symphony/console_snapshot.rb`
- Modify: `app/controllers/symphony/dashboard_controller.rb`
- Modify: `app/views/symphony/dashboard/show.html.erb`
- Modify: `app/assets/stylesheets/symphony/dashboard.css`
- Modify: `test/controllers/symphony/dashboard_controller_test.rb`
- Create: `test/models/symphony/console_snapshot_test.rb`

**Dashboard target:**
- project count
- active workflow count
- total running/retrying
- workflow health list
- recent failures

### Steps

- [ ] 실패 테스트 작성: workflow 2개 이상일 때 대시보드가 workflow row를 렌더하는지 검증
- [ ] `ConsoleSnapshot` 구현: `ManagedWorkflow.includes(...)` + runtime manager snapshot 집계
- [ ] `DashboardController#show`는 더 이상 `Symphony.orchestrator` singleton을 직접 읽지 않는다
- [ ] 뷰 개편: 전역 metric + workflow table + tracker sync/runtime status 표시
- [ ] empty state는 "active workflow 없음" 기준으로 바꾼다

Run: `bin/rails test test/models/symphony/console_snapshot_test.rb test/controllers/symphony/dashboard_controller_test.rb`
Expected: PASS

### Task 8: project/workflow 상세 read 화면 추가

**Files:**
- Create: `app/controllers/symphony/projects_controller.rb`
- Create: `app/controllers/symphony/workflows_controller.rb`
- Create: `app/views/symphony/projects/index.html.erb`
- Create: `app/views/symphony/projects/show.html.erb`
- Create: `app/views/symphony/workflows/show.html.erb`
- Modify: `config/routes.rb`
- Create: `test/controllers/symphony/projects_controller_test.rb`
- Create: `test/controllers/symphony/workflows_controller_test.rb`

**Workflow show target:**
- tracker connection 상태
- agent connection 요약
- runtime snapshot
- retry queue
- recent run attempts
- tracker capability badge

### Steps

- [ ] 컨트롤러 테스트 작성: projects index/show, workflows show
- [ ] project show에서 소속 workflow 목록과 last health 표시
- [ ] workflow show에서 runtime snapshot, retry rows, recent attempts, token usage를 렌더
- [ ] run history는 `RunAttempt.where(managed_workflow_id: ...)` 기반으로 20건만 노출
- [ ] tracker capability는 adapter가 제공하는 list를 뷰에 전달

Run: `bin/rails test test/controllers/symphony/projects_controller_test.rb test/controllers/symphony/workflows_controller_test.rb`
Expected: PASS

## Chunk 5: Admin Write UI and Capability-Based Tracker UX

### Task 9: project/workflow/connection CRUD 추가

**Files:**
- Create: `app/controllers/symphony/tracker_connections_controller.rb`
- Create: `app/controllers/symphony/agent_connections_controller.rb`
- Create: `app/views/symphony/projects/_form.html.erb`
- Create: `app/views/symphony/workflows/_form.html.erb`
- Create: `app/views/symphony/tracker_connections/_form.html.erb`
- Create: `app/views/symphony/agent_connections/_form.html.erb`
- Modify: `app/controllers/symphony/projects_controller.rb`
- Modify: `app/controllers/symphony/workflows_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/symphony/tracker_connections_controller_test.rb`
- Create: `test/controllers/symphony/agent_connections_controller_test.rb`

### Steps

- [ ] 프로젝트/워크플로/connection CRUD 테스트 작성
- [ ] workflow form에 `tracker_connection`, `agent_connection`, `prompt_template`, `runtime_config` 입력 추가
- [ ] 활성/비활성 상태 변경이 가능하도록 `status` 필드 노출
- [ ] form validation error를 화면에 표시
- [ ] workflow 저장 후 runtime manager refresh를 호출하거나, 최소한 다음 poll에서 반영되게 한다

Run: `bin/rails test test/controllers/symphony/tracker_connections_controller_test.rb test/controllers/symphony/agent_connections_controller_test.rb test/controllers/symphony/projects_controller_test.rb test/controllers/symphony/workflows_controller_test.rb`
Expected: PASS

### Task 10: tracker capability 모델 정리와 `database` tracker 연동

**Files:**
- Modify: `app/models/symphony/trackers/base.rb`
- Modify: `app/models/symphony/trackers/linear.rb`
- Create: `app/models/symphony/trackers/database.rb`
- Modify: `app/models/symphony/workflow_runtime_factory.rb`
- Create: `test/models/symphony/trackers/database_test.rb`
- Modify: `test/models/symphony/trackers/linear_test.rb`
- Modify: `app/controllers/symphony/workflows_controller.rb`
- Create: `app/controllers/symphony/managed_issues_controller.rb`
- Create: `app/views/symphony/managed_issues/index.html.erb`
- Create: `app/views/symphony/managed_issues/_form.html.erb`
- Create: `test/controllers/symphony/managed_issues_controller_test.rb`

**Capability contract:**
- always: `read_issues`, `read_issue_states`, `refresh`
- optional: `create_issue`, `update_issue`, `transition_issue`

### Steps

- [ ] `Trackers::Base#capabilities` 테스트 작성
- [ ] `Trackers::Linear`은 read-only capability만 반환
- [ ] `Trackers::Database`는 `ManagedIssue`를 source of truth로 사용하고 full CRUD capability 반환
- [ ] workflow detail 화면에서 capability badge와 action button 노출을 capability 기준으로 분기
- [ ] `ManagedIssuesController`는 `database` tracker workflow에서만 쓰기 액션 허용, 아니면 404 또는 422 처리
- [ ] `docs/plans/2026-03-13-tracker-database.md`의 구현 범위를 `ManagedIssue` 기준으로 맞춰 필요한 차이를 반영한다

Run: `bin/rails test test/models/symphony/trackers/database_test.rb test/controllers/symphony/managed_issues_controller_test.rb`
Expected: PASS

### Task 11: `github` tracker는 follow-up으로 연결

**Files:**
- Modify: `app/models/symphony/service_config.rb`
- Modify: `app/models/symphony/workflow_runtime_factory.rb`
- Follow existing plan: `docs/plans/2026-03-13-tracker-github-issues.md`

### Steps

- [ ] capability plumbing과 connection model이 먼저 안정화되기 전에는 `github` 구현에 착수하지 않는다
- [ ] `tracker.kind: github` validation과 factory wiring은 capability base landed 이후에만 붙인다
- [ ] GitHub adapter 상세 구현은 기존 dedicated plan을 그대로 따른다

Run: `bin/rails test test/models/symphony/service_config_test.rb`
Expected: PASS

## Chunk 6: Docs, Cutover, and Verification

### Task 12: 기존 `WORKFLOW.md`에서 DB model로 옮기는 cutover 경로 추가

**Files:**
- Create: `lib/tasks/symphony/import_workflow.rake`
- Create: `test/tasks/symphony/import_workflow_task_test.rb`
- Modify: `README.md`
- Modify: `docs/plans/2026-03-19-multi-project-admin-console-design.md`

### Steps

- [ ] import task 테스트 작성: 기존 `WORKFLOW.md`를 읽어 `ManagedProject`, `ManagedWorkflow`, connection record를 생성하는지 검증
- [ ] import task 구현: 파일 기반 config를 읽어 DB record로 1회 import
- [ ] import task는 credential 값을 평문으로 복사하지 않고 env var reference 문자열만 저장
- [ ] README에 "legacy file mode"와 "managed DB mode" 부팅 방법을 분리해서 문서화
- [ ] design doc에 최종적으로 implementation doc 링크와 결정사항을 반영

Run: `bin/rails test test/tasks/symphony/import_workflow_task_test.rb`
Expected: PASS

### Task 13: 전체 검증과 handoff

**Files:**
- Modify: `README.md`
- Modify: `docs/` 하위 운영 문서 중 DB 기반 관리 모델을 설명하는 문서들

### Steps

- [ ] workflow-scoped integration test 추가: project/workflow 생성 -> poll -> dispatch -> run attempt 기록 -> dashboard 표시
- [ ] full suite 실행: `bin/rails test`
- [ ] 수동 검증: workflow 2개 생성 후 root dashboard에서 각각 snapshot이 분리되어 보이는지 확인
- [ ] cutover note 작성: 남아 있는 후속 항목(`github`, webhook, auth`) 명시

Run: `bin/rails test`
Expected: PASS

## Implementation Notes

- 가장 위험한 변경은 `managed_workflow_id` 도입과 runtime persistence scoping이다. 여기서 전역 query가 하나라도 남으면 cross-workflow leakage가 발생한다.
- `WorkflowRuntimeManager`는 캐시일 뿐 source of truth가 아니다. job/controller는 언제든 factory로 context를 재구성할 수 있어야 한다.
- `ManagedIssue`와 `PersistedIssue`의 역할을 섞지 않는다. 전자는 tracker 원장, 후자는 runtime bookkeeping이다.
- first release에서 webhook을 넣지 않는다. poll이 안정화된 뒤 trigger layer를 추가한다.
- UI는 tracker kind 분기보다 capability list를 먼저 본다. kind별 `if/else`는 controller보다 adapter 계층에 가깝게 둔다.
