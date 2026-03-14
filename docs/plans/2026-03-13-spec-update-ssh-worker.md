# SPEC.md 업데이트 적용 구현 계획

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SPEC.md의 3가지 변경사항(정규화 단순화, comma-separated string 제거, SSH Worker Extension config+scheduling)을 코드에 반영한다.

**Architecture:** 기존 코드의 `.strip` 호출 제거(변경1), `parse_state_list`의 String 분기 제거(변경2), `ServiceConfig`에 SSH worker 필드 추가 + `Orchestrator`에 호스트별 동시성 제한 로직 추가(변경3). 실제 SSH 실행 어댑터는 이번 범위 밖.

**Tech Stack:** Ruby, Rails 8, Minitest

---

## Chunk 1: 정규화 단순화 + comma-separated string 제거

### Task 1: ServiceConfig — `.strip` 제거 및 String 분기 제거

**Files:**
- Modify: `app/models/symphony/service_config.rb:49-59` (strip 제거)
- Modify: `app/models/symphony/service_config.rb:125-131` (String 분기 제거)
- Modify: `test/models/symphony/service_config_test.rb:55-60` (comma-separated 테스트 제거)

- [ ] **Step 1: 테스트 수정 — comma-separated string 테스트를 Array-only 테스트로 교체**

`test/models/symphony/service_config_test.rb`의 `parses comma-separated state strings` 테스트를 삭제하고, Array 입력만 허용하는 테스트로 교체:

```ruby
test "parses array state config" do
  config = Symphony::ServiceConfig.new({
    "tracker" => { "active_states" => ["Todo", "In Progress", "Rework"] }
  })
  assert_equal ["Todo", "In Progress", "Rework"], config.active_states
end

test "falls back to default when active_states is a string" do
  config = Symphony::ServiceConfig.new({
    "tracker" => { "active_states" => "Todo, In Progress" }
  })
  assert_equal ["Todo", "In Progress"], config.active_states
end
```

- [ ] **Step 2: 테스트 실행 — String 분기가 아직 있으므로 두 번째 테스트 실패 확인**

Run: `bin/rails test test/models/symphony/service_config_test.rb -v`
Expected: `falls back to default when active_states is a string` FAIL

- [ ] **Step 3: `parse_state_list`에서 String 분기 제거**

`app/models/symphony/service_config.rb:125-131`을:

```ruby
def parse_state_list(raw, default)
  case raw
  when Array then raw.map(&:to_s)
  else default
  end
end
```

- [ ] **Step 4: `max_concurrent_agents_by_state`에서 `.strip` 제거**

`app/models/symphony/service_config.rb:53`:
```ruby
# before
hash[state.to_s.strip.downcase] = int_limit if int_limit > 0
# after
hash[state.to_s.downcase] = int_limit if int_limit > 0
```

`app/models/symphony/service_config.rb:58`:
```ruby
# before
max_concurrent_agents_by_state[state_name.to_s.strip.downcase]
# after
max_concurrent_agents_by_state[state_name.to_s.downcase]
```

- [ ] **Step 5: 테스트 실행 — 전체 통과 확인**

Run: `bin/rails test test/models/symphony/service_config_test.rb -v`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add app/models/symphony/service_config.rb test/models/symphony/service_config_test.rb
git commit -m "refactor: ServiceConfig에서 strip 제거, comma-separated string 지원 제거 (SPEC 업데이트)"
```

---

### Task 2: Orchestrator — `.strip` 제거

**Files:**
- Modify: `app/models/symphony/orchestrator.rb:215-216, 223, 302, 307`

- [ ] **Step 1: 기존 orchestrator 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/orchestrator_test.rb -v`
Expected: ALL PASS

- [ ] **Step 2: `.strip` 호출 일괄 제거**

`app/models/symphony/orchestrator.rb`에서 모든 `.strip.downcase`를 `.downcase`로 변경:

- Line 215: `terminal = config.terminal_states.map { |s| s.downcase }`
- Line 216: `active = config.active_states.map { |s| s.downcase }`
- Line 223: `state = issue&.state.to_s.downcase`
- Line 302: `e[:issue]&.state.to_s.downcase == state.to_s.downcase`
- Line 307: `issue.state.to_s.downcase == "todo"`

- [ ] **Step 3: 테스트 실행**

Run: `bin/rails test test/models/symphony/orchestrator_test.rb -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add app/models/symphony/orchestrator.rb
git commit -m "refactor: Orchestrator state 정규화에서 strip 제거 (SPEC 업데이트)"
```

---

### Task 3: Issue, Trackers::Memory — `.strip` 제거

**Files:**
- Modify: `app/models/symphony/issue.rb:23, 25`
- Modify: `app/models/symphony/trackers/memory.rb:28-29, 41-42`

- [ ] **Step 1: 기존 테스트 통과 확인**

Run: `bin/rails test test/models/symphony/issue_test.rb -v`
Expected: ALL PASS

- [ ] **Step 2: Issue#has_non_terminal_blockers?에서 `.strip` 제거**

`app/models/symphony/issue.rb`:
```ruby
def has_non_terminal_blockers?(terminal_states)
  normalized_terminal = terminal_states.map { |s| s.to_s.downcase }
  blocked_by.any? do |blocker|
    blocker_state = blocker["state"].to_s.downcase
    !normalized_terminal.include?(blocker_state)
  end
end
```

- [ ] **Step 3: Trackers::Memory에서 `.strip` 제거**

`app/models/symphony/trackers/memory.rb`:
- Line 28: `normalized = active_states.map { |s| s.to_s.downcase }`
- Line 29: `i.state.to_s.downcase`
- Line 41: `normalized = states.map { |s| s.to_s.downcase }`
- Line 42: `i.state.to_s.downcase`

- [ ] **Step 4: 전체 테스트 실행**

Run: `bin/rails test -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/symphony/issue.rb app/models/symphony/trackers/memory.rb
git commit -m "refactor: Issue, Trackers::Memory state 정규화에서 strip 제거 (SPEC 업데이트)"
```

---

## Chunk 2: SSH Worker Extension — Config + Scheduling

### Task 4: ServiceConfig에 SSH worker 필드 추가

**Files:**
- Modify: `app/models/symphony/service_config.rb`
- Modify: `test/models/symphony/service_config_test.rb`

- [ ] **Step 1: 테스트 작성 — SSH worker config 필드**

`test/models/symphony/service_config_test.rb`에 추가:

```ruby
test "ssh_hosts defaults to empty array" do
  config = Symphony::ServiceConfig.new({})
  assert_equal [], config.ssh_hosts
end

test "reads ssh_hosts from config" do
  config = Symphony::ServiceConfig.new({
    "worker" => { "ssh_hosts" => ["host1.example.com", "host2.example.com"] }
  })
  assert_equal ["host1.example.com", "host2.example.com"], config.ssh_hosts
end

test "max_concurrent_agents_per_host defaults to nil" do
  config = Symphony::ServiceConfig.new({})
  assert_nil config.max_concurrent_agents_per_host
end

test "reads max_concurrent_agents_per_host" do
  config = Symphony::ServiceConfig.new({
    "worker" => { "max_concurrent_agents_per_host" => 3 }
  })
  assert_equal 3, config.max_concurrent_agents_per_host
end

test "ssh_enabled? is true when ssh_hosts is non-empty" do
  config = Symphony::ServiceConfig.new({
    "worker" => { "ssh_hosts" => ["host1"] }
  })
  assert config.ssh_enabled?
end

test "ssh_enabled? is false when ssh_hosts is empty" do
  config = Symphony::ServiceConfig.new({})
  refute config.ssh_enabled?
end
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/symphony/service_config_test.rb -v`
Expected: FAIL (메서드 미정의)

- [ ] **Step 3: ServiceConfig에 SSH worker 접근자 구현**

`app/models/symphony/service_config.rb`의 Agent 섹션 아래에 추가:

```ruby
# Worker (SSH extension)
def ssh_hosts
  raw = dig("worker", "ssh_hosts")
  raw.is_a?(Array) ? raw.map(&:to_s) : []
end

def max_concurrent_agents_per_host
  integer_value("worker", "max_concurrent_agents_per_host", nil)
end

def ssh_enabled?
  ssh_hosts.any?
end
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `bin/rails test test/models/symphony/service_config_test.rb -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/symphony/service_config.rb test/models/symphony/service_config_test.rb
git commit -m "feat: ServiceConfig에 SSH worker 필드 추가 (ssh_hosts, max_concurrent_agents_per_host)"
```

---

### Task 5: Orchestrator에 호스트별 동시성 제한 추가

**Files:**
- Modify: `app/models/symphony/orchestrator.rb`
- Modify: `test/models/symphony/orchestrator_test.rb`

- [ ] **Step 1: 테스트 작성 — 호스트별 동시성 제한**

`test/models/symphony/orchestrator_test.rb`에 추가:

```ruby
test "host_slots_available? returns true when no ssh config" do
  assert @orchestrator.send(:host_slots_available?)
end

test "host_slots_available? respects per-host cap" do
  workflow_file = File.join(@root, "WORKFLOW_SSH.md")
  File.write(workflow_file, <<~YAML)
    ---
    tracker:
      kind: linear
      api_key: test
      project_slug: proj
    worker:
      ssh_hosts:
        - host1
        - host2
      max_concurrent_agents_per_host: 1
    ---
    Prompt
  YAML
  store = Symphony::WorkflowStore.new(workflow_file)

  orch = Symphony::Orchestrator.new(
    tracker: @tracker, workspace: @workspace, agent: nil,
    workflow_store: store,
    on_dispatch: ->(issue, attempt) { @dispatched << { issue: issue } }
  )

  orch.tick
  # max_concurrent_agents default=10, but 2 hosts * 1 per host = 2 max
  assert_equal 2, @dispatched.size
end
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/symphony/orchestrator_test.rb -v`
Expected: `host_slots_available? respects per-host cap` FAIL

- [ ] **Step 3: Orchestrator에 호스트 추적 및 제한 로직 구현**

`app/models/symphony/orchestrator.rb`에:

1. `do_dispatch`에서 `host` 할당 추가 (SSH 활성 시 라운드로빈 또는 가용 호스트 선택):

```ruby
def do_dispatch(issue, attempt: nil)
  host = select_host
  @claimed.add(issue.id)
  @running[issue.id] = {
    identifier: issue.identifier,
    issue: issue,
    host: host,
    started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000,
    # ... (기존 필드 유지)
  }
  # ...
end
```

2. `select_host` — SSH 비활성이면 `nil`, 활성이면 가용 슬롯이 있는 호스트 선택:

```ruby
def select_host
  return nil unless config.ssh_enabled?

  cap = config.max_concurrent_agents_per_host
  config.ssh_hosts.find do |host|
    next true unless cap
    running_on_host = @running.values.count { |e| e[:host] == host }
    running_on_host < cap
  end
end
```

3. `host_slots_available?` — dispatch 전 호스트 가용성 확인:

```ruby
def host_slots_available?
  return true unless config.ssh_enabled?
  select_host != nil
end
```

4. `dispatch_eligible`에서 `host_slots_available?` 체크 추가:

```ruby
def dispatch_eligible(candidates)
  candidates.each do |issue|
    break unless global_slots_available?
    break unless host_slots_available?
    # ... (기존 로직)
  end
end
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `bin/rails test test/models/symphony/orchestrator_test.rb -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/symphony/orchestrator.rb test/models/symphony/orchestrator_test.rb
git commit -m "feat: Orchestrator에 SSH 호스트별 동시성 제한 추가"
```

---

### Task 6: 전체 테스트 통과 확인 + 최종 커밋

**Files:** (없음 — 검증만)

- [ ] **Step 1: 전체 테스트 스위트 실행**

Run: `bin/rails test -v`
Expected: ALL PASS, 0 failures, 0 errors

- [ ] **Step 2: rubocop 실행 (있다면)**

Run: `bin/rubocop --autocorrect` 또는 프로젝트 lint 명령
Expected: 위반 없음

- [ ] **Step 3: 필요시 최종 수정 커밋**
