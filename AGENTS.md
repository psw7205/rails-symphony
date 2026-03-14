# Rails Symphony

Rails 8 + SQLite + Solid Queue 기반 Symphony 구현체.

## Environment

- Ruby / Rails 8, SQLite.
- Install deps: `bundle install`.
- Main quality gate: `bin/rails test`.

## Codebase-Specific Conventions

- Runtime config is loaded from `WORKFLOW.md` front matter via `Symphony::Workflow` and `Symphony::ServiceConfig`.
- Keep the implementation aligned with [`symphony/SPEC.md`](symphony/SPEC.md) where practical.
  - The implementation may be a superset of the spec.
  - The implementation must not conflict with the spec.
  - If implementation changes meaningfully alter the intended behavior, update the spec in the same
    change where practical so the spec stays current.
- All domain models live under `Symphony::` namespace (`app/models/symphony/`).
- Prefer adding config access through `Symphony::ServiceConfig` instead of ad-hoc env reads.
- Workspace safety is critical:
  - Never run agents with cwd in source repo.
  - Workspaces must stay under configured workspace root.
- Orchestrator behavior is stateful and concurrency-sensitive; preserve retry, reconciliation, and cleanup semantics.
- Follow structured logging conventions with required issue/session context fields.

## Tests and Validation

Run targeted tests while iterating, then run full gates before handoff.

```bash
bin/rails test
```

## Required Rules

- Keep changes narrowly scoped; avoid unrelated refactors.
- Follow existing module/style patterns in `app/models/symphony/`, `app/jobs/symphony/`.
- Match Rails conventions: thin controllers, domain logic in models/services.


## Docs Update Policy

If behavior/config changes, update docs in the same PR:

- `README.md` for project concept and goals.
- `docs/` for design decisions and plans.
