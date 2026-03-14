# SPEC Conformance Patches Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close high-impact SPEC conformance gaps identified in `docs/spec-comparison-2026-03-05.md` while keeping changes narrowly scoped.

**Architecture:** Strengthen orchestration preflight and dynamic config application at tick-time, tighten retry semantics and tracker pagination integrity, and align runtime accounting/error paths with SPEC intent. Each behavior change is test-first and mapped to an existing component boundary (config store, orchestrator, tracker adapter, runner, CLI parser).

**Tech Stack:** Ruby on Rails 8, Minitest, SQLite, Solid Queue, Liquid, Faraday.

---

### Task 1: Dispatch Preflight and Reload Guardrails

**Files:**
- Modify: `app/models/symphony/workflow_store.rb`
- Modify: `app/models/symphony/orchestrator.rb`
- Test: `test/models/symphony/workflow_store_test.rb`
- Test: `test/models/symphony/orchestrator_test.rb`

**Step 1: Write failing tests**
- Add test that invalid workflow reload sets an error surface in `WorkflowStore`.
- Add test that orchestrator dispatch is blocked when workflow store reports reload error.

**Step 2: Run tests to verify fail**
Run: `bin/rails test test/models/symphony/workflow_store_test.rb test/models/symphony/orchestrator_test.rb`

**Step 3: Implement minimal code**
- Track `last_error` in `WorkflowStore` and clear on successful reload.
- In orchestrator tick, call `reload_if_changed!` before preflight.
- Block dispatch when `workflow_store.last_error` is present.

**Step 4: Re-run tests**
Run: `bin/rails test test/models/symphony/workflow_store_test.rb test/models/symphony/orchestrator_test.rb`

### Task 2: Retry Semantics and Worker Termination Signaling

**Files:**
- Modify: `app/models/symphony/orchestrator.rb`
- Test: `test/models/symphony/orchestrator_test.rb`

**Step 1: Write failing tests**
- Retry fetch failure should requeue, not release claim.
- Slot exhaustion requeue should increment attempt.
- Reconciliation terminal/non-active path should request stop on known codex PID.

**Step 2: Run tests to verify fail**
Run: `bin/rails test test/models/symphony/orchestrator_test.rb`

**Step 3: Implement minimal code**
- Requeue on retry fetch failure with backoff and error reason.
- Increment attempt for slot exhaustion requeue.
- Add internal stop-request helper that signals tracked `codex_app_server_pid`.

**Step 4: Re-run tests**
Run: `bin/rails test test/models/symphony/orchestrator_test.rb`

### Task 3: Config/Workspace Runtime Semantics

**Files:**
- Modify: `app/models/symphony/service_config.rb`
- Modify: `app/models/symphony/workspace.rb`
- Modify: `app/models/symphony/orchestrator.rb`
- Modify: `app/models/symphony/trackers/linear.rb`
- Test: `test/models/symphony/service_config_test.rb`
- Test: `test/models/symphony/workspace_test.rb`

**Step 1: Write failing tests**
- `workspace.root` bare string should be preserved by config getter.
- Runtime config apply should update workspace hooks/timeout/root between ticks.

**Step 2: Run tests to verify fail**
Run: `bin/rails test test/models/symphony/service_config_test.rb test/models/symphony/workspace_test.rb test/models/symphony/orchestrator_test.rb`

**Step 3: Implement minimal code**
- Preserve bare relative workspace root in `ServiceConfig`.
- Add workspace reconfigure API and apply it from orchestrator each tick.
- Add optional tracker reconfigure hook for linear endpoint/api/project changes.

**Step 4: Re-run tests**
Run: `bin/rails test test/models/symphony/service_config_test.rb test/models/symphony/workspace_test.rb test/models/symphony/orchestrator_test.rb`

### Task 4: Prompt Error Path and Token Accounting

**Files:**
- Modify: `app/models/symphony/agent_runner.rb`
- Modify: `app/models/symphony/orchestrator.rb`
- Test: `test/models/symphony/agent_runner_test.rb`
- Test: `test/models/symphony/orchestrator_snapshot_test.rb`

**Step 1: Write failing tests**
- Prompt render error should return structured runner error (not uncaught exception).
- Token totals should apply monotonic delta semantics per running entry.

**Step 2: Run tests to verify fail**
Run: `bin/rails test test/models/symphony/agent_runner_test.rb test/models/symphony/orchestrator_snapshot_test.rb`

**Step 3: Implement minimal code**
- Rescue prompt build/render errors in runner turn loop and return error payload.
- Track last reported usage counters in running entry and accumulate positive deltas only.

**Step 4: Re-run tests**
Run: `bin/rails test test/models/symphony/agent_runner_test.rb test/models/symphony/orchestrator_snapshot_test.rb`

### Task 5: Linear Pagination Integrity and CLI Parsing Edge Case

**Files:**
- Modify: `app/models/symphony/trackers/linear.rb`
- Modify: `bin/symphony`
- Test: `test/models/symphony/trackers/linear_test.rb`
- Test: `test/conformance/cli_lifecycle_test.rb`

**Step 1: Write failing tests**
- Return `:linear_missing_end_cursor` when `hasNextPage=true` and `endCursor` missing.
- CLI should accept `--port` before positional workflow argument.

**Step 2: Run tests to verify fail**
Run: `bin/rails test test/models/symphony/trackers/linear_test.rb test/conformance/cli_lifecycle_test.rb`

**Step 3: Implement minimal code**
- Enforce endCursor integrity check in linear fetch pagination.
- Parse CLI args so first non-flag token becomes workflow path.

**Step 4: Re-run tests**
Run: `bin/rails test test/models/symphony/trackers/linear_test.rb test/conformance/cli_lifecycle_test.rb`

### Task 6: Final Verification

**Files:**
- Verify only

**Step 1: Run focused suites**
Run: `bin/rails test test/models/symphony test/conformance test/controllers/api/v1 test/integration/symphony_e2e_test.rb`

**Step 2: Run full suite**
Run: `bin/rails test`

**Step 3: Record outcomes in final handoff**
- List changed files and mapped SPEC gaps.
- Report any residual non-conformances not addressed in this patch.
