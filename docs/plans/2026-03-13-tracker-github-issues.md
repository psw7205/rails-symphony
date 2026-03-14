# Trackers::GithubIssues 구현 계획

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan.

**Goal:** GitHub Issues를 Symphony 트래커로 사용할 수 있는 `Trackers::GithubIssues` 어댑터 구현

**Architecture:** GitHub REST API v3를 Faraday로 호출하여 이슈를 조회하고, GitHub 라벨을 Symphony state로 매핑하는 어댑터. `Trackers::Base` 인터페이스(3개 메서드)를 구현하며, `Trackers::Linear`과 동일한 패턴을 따른다. GitHub Issues는 open/closed만 있으므로 라벨 기반 state 매핑이 핵심 설계.

**Tech Stack:** Faraday (HTTP), GitHub REST API v3, WebMock (테스트)

---

## Task 1: GitHub API 클라이언트

GitHub REST API v3 호출을 담당하는 내부 클라이언트. Trackers::GithubIssues 내부 private 메서드로 구현.

**Files:**
- Create: `app/models/symphony/trackers/github_issues.rb`
- Create: `test/models/symphony/trackers/github_issues_test.rb`

**Config 필드:**
- `tracker.kind: "github"`
- `tracker.repo`: `"owner/repo"` 형식 (필수)
- `tracker.api_key`: `$GITHUB_TOKEN` (필수)
- `tracker.endpoint`: GitHub Enterprise용 (기본값 `https://api.github.com`)

**API 엔드포인트:**
- `GET /repos/{owner}/{repo}/issues?labels={label}&state=open&per_page=100&page={n}` — 라벨별 이슈 목록
- `GET /repos/{owner}/{repo}/issues/{number}` — 단건 조회 (fetch_issue_states_by_ids용)

### Steps

- [ ] **1-1.** `test/models/symphony/trackers/github_issues_test.rb` 생성. 기본 setup 작성: `WebMock` 활성화, `@tracker = Trackers::GithubIssues.new(api_key:, repo:, endpoint:)` 초기화.
- [ ] **1-2.** 실패 테스트 작성: `test "initializes Faraday connection with correct base URL and auth header"` — `@tracker`가 생성되었는지, 내부 `@conn`이 존재하는지 확인.
- [ ] **1-3.** `app/models/symphony/trackers/github_issues.rb` 생성. `initialize(api_key:, repo:, endpoint:)` + `build_connection` 구현. `Faraday.new(url: endpoint)` + `Authorization: token #{api_key}` + `Accept: application/vnd.github+json` 헤더.
  - ref: `app/models/symphony/trackers/linear.rb:L59-72` (동일 패턴)
- [ ] **1-4.** 실패 테스트 작성: `test "list_issues fetches paginated issues from GitHub API"` — WebMock으로 `GET /repos/owner/repo/issues?labels=Todo&state=open&per_page=100` stub. 2페이지 pagination (Link 헤더) 포함.
- [ ] **1-5.** private `list_issues(label:)` 메서드 구현. `per_page=100`, pagination은 Link 헤더의 `rel="next"` 파싱. 최대 10페이지 safety limit.
- [ ] **1-6.** 실패 테스트 작성: `test "handles API error (401 Unauthorized)"` — status 401 반환 시 `{ error: :github_api_status, status: 401 }`.
- [ ] **1-7.** 실패 테스트 작성: `test "handles transport error"` — `stub_request.to_timeout` 시 `{ error: :github_transport_error }`.
- [ ] **1-8.** 에러 핸들링 구현: HTTP status != 200 → `{ error: :github_api_status }`, `Faraday::Error` → `{ error: :github_transport_error }`.
  - ref: `app/models/symphony/trackers/linear.rb:L136-156` (동일 패턴)
- [ ] **1-9.** 테스트 통과 확인: `bin/rails test test/models/symphony/trackers/github_issues_test.rb`
- [ ] **1-10.** 커밋: `feat: add GitHub API client in Trackers::GithubIssues`

---

## Task 2: Trackers::GithubIssues 어댑터 (Base 인터페이스 구현)

`Trackers::Base`의 3개 메서드 구현 + GitHub Issue → `Symphony::Issue` 변환.

**State 매핑 규칙:**
- GitHub Issue의 라벨 중 `active_states`에 매칭되는 첫 번째 라벨이 state
- 매칭 라벨 없고 open 상태면 `active_states.first`를 기본 state로 할당
- closed 이슈는 조회 대상이 아님 (API에서 `state=open`으로 필터)

**Issue 필드 매핑:**
| Symphony Issue | GitHub Source |
|---|---|
| `id` | `node_id` (globally unique) |
| `identifier` | `"owner/repo#number"` |
| `title` | `title` |
| `description` | `body` |
| `priority` | 라벨에서 `priority:N` 패턴 파싱, 없으면 nil |
| `state` | 라벨 기반 매핑 (위 규칙) |
| `branch_name` | `"#{identifier.parameterize}"` (e.g., `owner-repo-123`) |
| `url` | `html_url` |
| `labels` | `labels[].name` (lowercase) |
| `blocked_by` | `[]` (1차 구현에서 빈 배열) |
| `created_at` | `created_at` (ISO 8601) |
| `updated_at` | `updated_at` (ISO 8601) |

### Steps

- [ ] **2-1.** 실패 테스트: `test "fetch_candidate_issues returns issues matching active_states labels"` — `active_states: ["Todo", "In Progress"]`로 호출. WebMock stub 2개 (라벨 "Todo", "In Progress" 각각). 반환된 issues의 state, id, identifier 검증.
- [ ] **2-2.** `fetch_candidate_issues(active_states:)` 구현. 각 active_state를 라벨로 사용해 `list_issues(label:)` 호출 후 합산. 중복 제거 (같은 이슈에 "Todo"와 "In Progress" 라벨이 동시에 있는 경우 `node_id` 기준).
- [ ] **2-3.** 실패 테스트: `test "normalize_issue maps GitHub issue to Symphony::Issue"` — 단건 GitHub JSON → `Symphony::Issue` 필드 전체 검증.
- [ ] **2-4.** private `normalize_issue(gh_issue, state:, repo:)` 구현. 위 매핑 테이블 기준.
- [ ] **2-5.** 실패 테스트: `test "extracts priority from priority:N label"` — `labels: [{ name: "priority:2" }, { name: "bug" }]` → `priority == 2`.
- [ ] **2-6.** private `extract_priority(labels)` 구현. `/\Apriority:(\d+)\z/i` 매칭.
- [ ] **2-7.** 실패 테스트: `test "fetch_issue_states_by_ids returns issues by node_id"` — ids `["MDU6SXN..1", "MDU6SXN..2"]` 전달. WebMock으로 `GET /repos/owner/repo/issues` stub (전체 조회 후 필터). 반환된 issues의 id, state 검증.
- [ ] **2-8.** `fetch_issue_states_by_ids(ids)` 구현. 전략: `GET /repos/{owner}/{repo}/issues?state=all&per_page=100` 조회 후 `node_id`로 필터. (GitHub API에 node_id 필터 없으므로 클라이언트 사이드 필터링. 이슈 수가 많은 프로젝트에서는 개별 조회가 나을 수 있으나, 1차는 단순 구현.)
  - **주의:** ids가 빈 배열이면 API 호출 없이 `{ ok: true, issues: [] }` 즉시 반환.
- [ ] **2-9.** 실패 테스트: `test "fetch_issues_by_states returns issues matching given states"` — `states: ["Done"]` 전달. 검증.
- [ ] **2-10.** `fetch_issues_by_states(states)` 구현. `fetch_candidate_issues`와 동일 로직 (states를 라벨로 사용).
- [ ] **2-11.** 실패 테스트: `test "reconfigure updates api_key and repo, rebuilds connection on endpoint change"`.
- [ ] **2-12.** `reconfigure(api_key:, repo:, endpoint:)` 구현.
  - ref: `app/models/symphony/trackers/linear.rb:L66-73`
- [ ] **2-13.** 테스트 전체 통과 확인: `bin/rails test test/models/symphony/trackers/github_issues_test.rb`
- [ ] **2-14.** 커밋: `feat: implement Trackers::GithubIssues adapter with Base interface`

---

## Task 3: ServiceConfig에 github tracker kind 지원 추가

**Files:**
- Modify: `app/models/symphony/service_config.rb`
- Modify: `test/models/symphony/service_config_test.rb`

### Steps

- [ ] **3-1.** 실패 테스트: `test "validate! accepts tracker.kind github with required fields"` — `{ "tracker" => { "kind" => "github", "repo" => "owner/repo", "api_key" => "ghp_xxx" } }` → `:ok`.
- [ ] **3-2.** 실패 테스트: `test "validate! rejects github tracker without repo"` — `repo` 누락 시 에러 메시지 포함 검증.
- [ ] **3-3.** 실패 테스트: `test "validate! rejects github tracker without api_key"` — `api_key` 누락 시 에러.
- [ ] **3-4.** `ServiceConfig` 수정:
  - `validate!`의 kind 검증에 `"github"` 추가
  - `github` kind일 때 `tracker.api_key`, `tracker.repo` 필수 검증 추가
  - `tracker_repo` 접근자 메서드 추가
  - `tracker_api_key`에 `GITHUB_TOKEN` fallback 추가
  - `tracker_endpoint`의 기본값을 kind에 따라 분기: linear → Linear 엔드포인트, github → `https://api.github.com`
- [ ] **3-5.** 실패 테스트: `test "tracker_api_key falls back to GITHUB_TOKEN for github kind"` — ENV stub으로 검증.
- [ ] **3-6.** 실패 테스트: `test "tracker_endpoint defaults to GitHub API for github kind"` — endpoint 미지정 시 `https://api.github.com` 반환 검증.
- [ ] **3-7.** 위 테스트들 통과하도록 구현 완료.
- [ ] **3-8.** 기존 테스트 전체 통과 확인: `bin/rails test test/models/symphony/service_config_test.rb`
- [ ] **3-9.** 커밋: `feat: add github tracker kind support to ServiceConfig`

---

## Task 4: 통합 테스트

WebMock 기반 E2E 시나리오 테스트. 실제 GitHub API 응답 형태를 fixture로 사용.

**Files:**
- Create: `test/integration/symphony/trackers/github_issues_integration_test.rb`
- Create: `test/fixtures/files/github/issues_page1.json`
- Create: `test/fixtures/files/github/issues_page2.json`
- Create: `test/fixtures/files/github/issue_single.json`

### Steps

- [ ] **4-1.** GitHub API 응답 fixture JSON 파일 생성. 실제 API 응답 스키마 기준 (`node_id`, `number`, `title`, `body`, `state`, `labels`, `html_url`, `created_at`, `updated_at` 등 포함). `issues_page1.json` (2건), `issues_page2.json` (1건), `issue_single.json` (1건).
- [ ] **4-2.** 통합 테스트 작성: `test "full workflow: config parse → tracker init → fetch issues"` — YAML config 파싱 → `ServiceConfig` → `Trackers::GithubIssues` 생성 → `fetch_candidate_issues` 호출 → 결과 검증.
- [ ] **4-3.** 통합 테스트 작성: `test "pagination across multiple pages"` — Link 헤더로 2페이지 pagination stub → 전체 3건 반환 검증.
- [ ] **4-4.** 통합 테스트 작성: `test "issue with no matching state label defaults to first active_state"` — 라벨 없는 open 이슈의 state가 `active_states.first`로 매핑되는지 검증.
- [ ] **4-5.** 테스트 통과 확인: `bin/rails test test/integration/symphony/trackers/github_issues_integration_test.rb`
- [ ] **4-6.** 전체 테스트 통과 확인: `bin/rails test`
- [ ] **4-7.** 커밋: `test: add integration tests for Trackers::GithubIssues`
