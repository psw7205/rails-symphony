# Trackers::Database 구현 계획

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan.

**Goal:** 외부 트래커 없이 웹 UI로 이슈를 직접 관리하는 DB 기반 자체 트래커 (`tracker.kind: database`) 구현.

**Architecture:** 기존 `symphony_issues` 테이블과 `PersistedIssue` AR 모델을 source of truth로 재활용. `Trackers::Database` 어댑터가 `PersistedIssue`를 직접 쿼리하여 `Trackers::Base` 인터페이스를 구현하고, 웹 CRUD 컨트롤러로 이슈 생성/편집/상태 변경을 제공. `identifier`는 `SYM-N` 시퀀스로 자동 생성.

**Tech Stack:** Rails 8, SQLite3, PersistedIssue AR model, ERB views

---

## Task 1: Trackers::Database 어댑터

**Files:**
- Create: `test/models/symphony/trackers/database_test.rb`
- Create: `app/models/symphony/trackers/database.rb`

**Ref:** `app/models/symphony/trackers/base.rb`, `app/models/symphony/trackers/memory.rb`, `test/models/symphony/trackers/memory_test.rb`

### Step 1: 실패하는 테스트 작성

- [ ] `test/models/symphony/trackers/database_test.rb` 생성
- [ ] `PersistedIssue`로 테스트 데이터 세팅 (setup에서 3개 이슈 생성: Todo, In Progress, Done)
- [ ] `fetch_candidate_issues(active_states:)` — active state 이슈만 반환, `{ ok: true, issues: [...] }` 형태
- [ ] `fetch_issue_states_by_ids(ids)` — ID 목록으로 이슈 조회
- [ ] `fetch_issues_by_states(states)` — state 목록으로 필터, 대소문자 무시
- [ ] `fetch_issues_by_states([])` — 빈 배열이면 빈 결과
- [ ] 반환되는 각 이슈가 `Symphony::Issue` 인스턴스인지 확인

Run: `bin/rails test test/models/symphony/trackers/database_test.rb` → 실패 확인

### Step 2: 어댑터 구현

- [ ] `app/models/symphony/trackers/database.rb` 생성
- [ ] `Symphony::Trackers::Database < Base` 클래스
- [ ] `fetch_candidate_issues` — `PersistedIssue`에서 active_states로 case-insensitive 쿼리, 결과를 `Symphony::Issue`로 변환
- [ ] `fetch_issue_states_by_ids` — `PersistedIssue.where(id: ids)` 쿼리, `Issue`로 변환
- [ ] `fetch_issues_by_states` — states가 비어있으면 빈 결과, 아니면 state로 필터
- [ ] private `to_issue(record)` 헬퍼 — `PersistedIssue` → `Symphony::Issue` 변환

Run: `bin/rails test test/models/symphony/trackers/database_test.rb` → 통과 확인

### Step 3: 커밋

```
feat: add Trackers::Database adapter querying PersistedIssue directly
```

---

## Task 2: ServiceConfig에 database tracker kind 지원 추가

**Files:**
- Modify: `test/models/symphony/service_config_test.rb`
- Modify: `app/models/symphony/service_config.rb`

**Ref:** `app/models/symphony/service_config.rb:L76` — `validate!` 메서드의 kind 검증 로직

### Step 1: 실패하는 테스트 작성

- [ ] `tracker.kind: "database"` 설정으로 `validate!`가 `:ok` 반환하는 테스트 추가
- [ ] `tracker.kind: "database"`일 때 `api_key`, `project_slug` 불필요 확인

Run: `bin/rails test test/models/symphony/service_config_test.rb` → 실패 확인

### Step 2: validate! 수정

- [ ] `service_config.rb:L76`의 조건에 `"database"` 추가: `tracker_kind != "linear" && tracker_kind != "memory" && tracker_kind != "database"`

Run: `bin/rails test test/models/symphony/service_config_test.rb` → 통과 확인

### Step 3: 커밋

```
feat: support tracker.kind "database" in ServiceConfig validation
```

---

## Task 3: identifier 자동 생성 로직 (SYM-N 시퀀스)

**Files:**
- Modify: `test/models/symphony/persisted_issue_test.rb`
- Modify: `app/models/symphony/persisted_issue.rb`

### Step 1: 실패하는 테스트 작성

- [ ] `PersistedIssue`를 identifier 없이 생성 시 `SYM-1` 자동 부여 테스트
- [ ] 두 번째 이슈 생성 시 `SYM-2` 부여 테스트
- [ ] 기존에 `SYM-5`가 있으면 다음은 `SYM-6` 테스트
- [ ] identifier가 명시적으로 주어진 경우 (Linear 트래커 등) 덮어쓰지 않는 테스트

Run: `bin/rails test test/models/symphony/persisted_issue_test.rb` → 실패 확인

### Step 2: before_validation 콜백 구현

- [ ] `persisted_issue.rb`에 `before_validation :assign_identifier, on: :create` 추가
- [ ] `assign_identifier` — `identifier`가 비어있을 때만 실행
- [ ] 시퀀스 계산: `SYM-` 프리픽스를 가진 identifier 중 최대 숫자 + 1 (없으면 1)
- [ ] `self.identifier = "SYM-#{next_number}"`

Run: `bin/rails test test/models/symphony/persisted_issue_test.rb` → 통과 확인

### Step 3: id 자동 생성도 추가

- [ ] `id`가 string PK이므로 비어있을 때 `SecureRandom.uuid` 자동 부여 (before_validation)
- [ ] 테스트 추가: id 없이 생성해도 UUID가 할당되는지 확인

Run: `bin/rails test test/models/symphony/persisted_issue_test.rb` → 통과 확인

### Step 4: 커밋

```
feat: auto-generate SYM-N identifier and UUID id for PersistedIssue
```

---

## Task 4: 웹 이슈 CRUD 컨트롤러 + 뷰

**Files:**
- Create: `test/controllers/symphony/issues_controller_test.rb`
- Create: `app/controllers/symphony/issues_controller.rb`
- Create: `app/views/symphony/issues/index.html.erb`
- Create: `app/views/symphony/issues/new.html.erb`
- Create: `app/views/symphony/issues/edit.html.erb`
- Create: `app/views/symphony/issues/_form.html.erb`
- Modify: `config/routes.rb`

**Ref:** `app/controllers/symphony/dashboard_controller.rb`, `app/views/symphony/dashboard/show.html.erb` (기존 스타일 참고)

### Step 1: 라우트 추가

- [ ] `config/routes.rb`에 `resources :issues, controller: "symphony/issues"` 추가 (namespace 고려)
- [ ] `show` 액션은 불필요 — `index`, `new`, `create`, `edit`, `update`, `destroy`만

### Step 2: 컨트롤러 테스트 작성

- [ ] `GET /issues` — 이슈 목록 200 응답
- [ ] `GET /issues/new` — 생성 폼 200 응답
- [ ] `POST /issues` — 이슈 생성 후 리다이렉트, `PersistedIssue.count` 증가
- [ ] `GET /issues/:id/edit` — 편집 폼 200 응답
- [ ] `PATCH /issues/:id` — 이슈 업데이트 후 리다이렉트
- [ ] `DELETE /issues/:id` — 이슈 삭제 후 리다이렉트

Run: `bin/rails test test/controllers/symphony/issues_controller_test.rb` → 실패 확인

### Step 3: 컨트롤러 구현

- [ ] `Symphony::IssuesController < ApplicationController`
- [ ] `index` — `@issues = PersistedIssue.order(created_at: :desc)`
- [ ] `new` — `@issue = PersistedIssue.new(state: "Todo")`
- [ ] `create` — strong params (`title`, `description`, `priority`, `state`), 성공 시 issues 목록으로 리다이렉트
- [ ] `edit` — `@issue = PersistedIssue.find(params[:id])`
- [ ] `update` — strong params, 성공 시 issues 목록으로 리다이렉트
- [ ] `destroy` — 삭제 후 리다이렉트
- [ ] private `issue_params` — `permit(:title, :description, :priority, :state)`

### Step 4: 뷰 구현

- [ ] `_form.html.erb` — title, description (textarea), priority (select 0-4), state (select: Todo/In Progress/Done/Closed/Cancelled)
- [ ] `index.html.erb` — 테이블: identifier, title, state, priority, 생성일, 편집/삭제 링크. 상단에 "New Issue" 버튼
- [ ] `new.html.erb` — form partial 렌더
- [ ] `edit.html.erb` — form partial 렌더
- [ ] 기존 대시보드 CSS 클래스 (`section-card`, `data-table`, `metric-card` 등) 재활용

Run: `bin/rails test test/controllers/symphony/issues_controller_test.rb` → 통과 확인

### Step 5: 커밋

```
feat: add web CRUD for issues (controller, views, routes)
```

---

## Task 5: 대시보드 연동

**Files:**
- Modify: `app/views/symphony/dashboard/show.html.erb`
- Modify: `app/views/layouts/application.html.erb` (내비게이션에 Issues 링크)

### Step 1: 대시보드에 이슈 관리 링크 추가

- [ ] 대시보드 hero 영역 또는 nav에 "Manage Issues" 링크 추가 (issues 목록 경로)
- [ ] DB 트래커 모드일 때만 표시하거나, 항상 표시 (PersistedIssue 기반이므로 항상 표시해도 무방)

### Step 2: 이슈 목록에 대시보드 복귀 링크

- [ ] issues index 상단에 "Back to Dashboard" 링크

### Step 3: 커밋

```
feat: link dashboard and issues management pages
```

---

## Task 6: 전체 통합 테스트

**Files:**
- Create: `test/integration/symphony/database_tracker_integration_test.rb`

### Step 1: 통합 테스트 작성

- [ ] 웹 UI로 이슈 생성 → `Trackers::Database`로 `fetch_candidate_issues` 호출 → 생성한 이슈 반환 확인
- [ ] 웹 UI로 이슈 상태 변경 → `fetch_issues_by_states`로 변경된 상태 확인
- [ ] identifier 자동 생성 확인 — 웹 UI로 2개 생성 시 `SYM-1`, `SYM-2` 순서
- [ ] `ServiceConfig.new({"tracker" => {"kind" => "database"}, "codex" => {"command" => "codex"}}).validate!` → `:ok`

Run: `bin/rails test test/integration/symphony/database_tracker_integration_test.rb` → 통과 확인

### Step 2: 전체 테스트 스위트 실행

Run: `bin/rails test` → 기존 테스트 포함 전체 통과 확인

### Step 3: 커밋

```
test: add integration tests for database tracker end-to-end flow
```
