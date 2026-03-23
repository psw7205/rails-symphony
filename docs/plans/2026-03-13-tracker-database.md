# Trackers::Database 구현 계획

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan.

**Goal:** 외부 tracker 없이 admin console 안에서 이슈를 직접 관리하는 DB 기반 tracker (`tracker.kind: database`)를 제공한다.

**Relationship to the multi-project console plan:** 이 문서는 `docs/plans/2026-03-19-multi-project-admin-console-implementation.md`의 database tracker slice를 보조한다. 구현 source of truth는 `ManagedWorkflow` + `ManagedIssue` 기반 멀티-workflow 콘솔 모델이다.

**Architecture:** `Trackers::Database`는 더 이상 runtime bookkeeping 테이블(`symphony_issues`)을 재사용하지 않는다. 대신 `symphony_managed_issues` / `Symphony::ManagedIssue`를 database tracker workflow의 ledger로 사용하고, 모든 read/write는 `managed_workflow_id`로 스코프한다. 어드민 UI는 전역 issues 화면이 아니라 workflow-scoped `ManagedIssuesController` (`/workflows/:workflow_id/issues`)를 통해 CRUD를 제공한다. runtime wiring은 `WorkflowRuntimeFactory`가 `tracker.kind: database`인 workflow에 대해 `Trackers::Database.new(managed_workflow: ...)`를 구성한다.

**Tech Stack:** Rails 8, SQLite3, `Symphony::ManagedIssue`, `Symphony::ManagedWorkflow`, ERB views, workflow-scoped runtime factory

---

## Locked Decisions

- `PersistedIssue`는 runtime persistence/cache 용도로 유지하고 database tracker ledger로 재사용하지 않는다.
- database tracker ledger의 source of truth는 `Symphony::ManagedIssue`다.
- ledger query와 mutation은 항상 `managed_workflow_id` 기준으로 제한한다.
- database tracker write UI는 `tracker_connection.kind == "database"` workflow에서만 허용한다.
- workflow detail 화면의 action 노출은 tracker kind 하드코딩보다 capability를 기준으로 한다.
- `identifier` 자동 생성(`SYM-N`)은 이 plan의 범위에 두지 않는다. 현재는 admin UI 입력값을 저장한다.

## Success Criteria

- `Trackers::Database`가 `ManagedIssue`를 읽어 `Symphony::Issue` 목록을 반환한다.
- database tracker workflow는 `create_issue`, `update_issue`, `transition_issue` capability를 가진다.
- `WorkflowRuntimeFactory`가 database tracker workflow를 올바른 adapter로 조립한다.
- `/workflows/:workflow_id/issues` CRUD가 database tracker workflow에서만 동작한다.
- non-database workflow에서는 managed issue write path가 404로 차단된다.
- 관련 테스트와 계획 문서가 현재 `ManagedIssue` 기반 구조와 충돌하지 않는다.

## Out of Scope

- 외부 tracker와의 양방향 동기화
- identifier 자동 시퀀스 발급
- workflow 범위를 넘는 전역 issues CRUD
- webhook 기반 create/update trigger

## Task 1: Database tracker adapter

**Files:**
- `app/models/symphony/trackers/database.rb`
- `test/models/symphony/trackers/database_test.rb`

### Steps

- [ ] `Trackers::Database`는 `managed_workflow:`를 받아 초기화한다
- [ ] capability는 `read_issues`, `read_issue_states`, `refresh`, `create_issue`, `update_issue`, `transition_issue`
- [ ] `fetch_candidate_issues(active_states:)`는 workflow-scoped `ManagedIssue`를 읽는다
- [ ] `fetch_issue_states_by_ids(ids)`는 현재 workflow에 속한 ledger row만 반환한다
- [ ] `fetch_issues_by_states(states)`는 상태를 case-insensitive로 필터한다
- [ ] 각 결과는 `Symphony::Issue`로 정규화한다

Run: `bin/rails test test/models/symphony/trackers/database_test.rb`
Expected: PASS

## Task 2: Config and runtime wiring

**Files:**
- `app/models/symphony/service_config.rb`
- `app/models/symphony/workflow_runtime_factory.rb`
- `test/models/symphony/service_config_test.rb`
- `test/models/symphony/workflow_runtime_factory_test.rb`

### Steps

- [ ] `ServiceConfig` validation이 `tracker.kind: database`를 허용한다
- [ ] `WorkflowRuntimeFactory.build_tracker`가 `database` kind를 `Trackers::Database`로 연결한다
- [ ] factory는 workflow record를 함께 넘겨 workflow-scoped ledger access를 보장한다
- [ ] database tracker workflow snapshot이 다른 workflow ledger와 섞이지 않는지 검증한다

Run: `bin/rails test test/models/symphony/service_config_test.rb test/models/symphony/workflow_runtime_factory_test.rb`
Expected: PASS

## Task 3: Workflow-scoped managed issue CRUD

**Files:**
- `app/controllers/symphony/managed_issues_controller.rb`
- `app/views/symphony/managed_issues/index.html.erb`
- `app/views/symphony/managed_issues/new.html.erb`
- `app/views/symphony/managed_issues/edit.html.erb`
- `app/views/symphony/managed_issues/_form.html.erb`
- `config/routes.rb`
- `test/controllers/symphony/managed_issues_controller_test.rb`

### Steps

- [ ] routes는 `/workflows/:workflow_id/issues` 아래에만 노출한다
- [ ] `index/new/create/edit/update/destroy`는 database tracker workflow에서만 허용한다
- [ ] member lookup은 `@workflow.managed_issues.find(...)`로 제한한다
- [ ] 다른 workflow issue를 잘못 수정/삭제하지 못하게 테스트로 고정한다
- [ ] non-database workflow write path는 404로 차단한다
- [ ] validation error와 malformed input은 `422`로 다시 렌더한다

Run: `bin/rails test test/controllers/symphony/managed_issues_controller_test.rb`
Expected: PASS

## Task 4: Capability-based workflow UX

**Files:**
- `app/controllers/symphony/workflows_controller.rb`
- `app/views/symphony/workflows/show.html.erb`
- `test/controllers/symphony/workflows_controller_test.rb`
- `test/models/symphony/trackers/base_test.rb`
- `test/models/symphony/trackers/linear_test.rb`

### Steps

- [ ] base capability contract를 `read_issues`, `read_issue_states`, `refresh`로 고정한다
- [ ] `Trackers::Linear`은 read-only capability만 반환한다
- [ ] workflow detail은 capability list를 렌더한다
- [ ] managed issue action link는 `create_issue` capability가 있을 때만 노출한다
- [ ] read-only tracker workflow에서는 managed issue action이 숨겨진다

Run: `bin/rails test test/controllers/symphony/workflows_controller_test.rb test/models/symphony/trackers/base_test.rb test/models/symphony/trackers/linear_test.rb`
Expected: PASS

## Task 5: Verification and docs sync

**Files:**
- `docs/plans/2026-03-19-multi-project-admin-console-implementation.md`
- `docs/plans/2026-03-19-multi-project-admin-console-design.md`
- `docs/plans/2026-03-13-tracker-database.md`

### Steps

- [ ] database tracker 문서가 `ManagedIssue` 기반 구현과 충돌하지 않는지 확인한다
- [ ] multi-project console plan의 Task 10 범위와 terminology를 맞춘다
- [ ] verification은 managed issue CRUD, workflow show, tracker tests를 묶어 실행한다

Run: `bin/rails test test/models/symphony/trackers/database_test.rb test/controllers/symphony/managed_issues_controller_test.rb test/controllers/symphony/workflows_controller_test.rb`
Expected: PASS
