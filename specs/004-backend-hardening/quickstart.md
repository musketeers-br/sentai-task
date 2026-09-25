# Quickstart — 004 Backend Hardening (minimum acceptance path)

Proves the v1 acceptance path on the real instance (spec Clarifications, "minimum shippable
scope"). Supersedes the canonical-flow steps of
[spec 003 quickstart](../003-backend-objectscript/quickstart.md) for v1.

Support set: **`integrity-check` only** (D-1 amended).

## Prerequisites

- IRIS 2026.2 container `sentai-task-iris-1`, namespace `IRISAPP`, web server `localhost:52773`
  (same as [spec 003 evidence](../003-backend-objectscript/quickstart-evidence.md)).
- Operator credential for `POST /api/admin/login` (HTTP Basic). Access tokens live **60 s** — log
  in again before each block.
- Base URL: `http://localhost:52773/csp/sentai/api/v1`.
- Record status + body per call into `evidence/quickstart-http-<date>.json` (no tokens).

## Automated suite

```bash
docker exec -it sentai-task-iris-1 iris session iris -U IRISAPP 'zpm "test sentai-task -v -only"'
```

Expected: every pre-existing test (86) plus the new ones pass; 0 failures.

## Acceptance

| Block | Call | Expected |
|---|---|---|
| (a) | `POST /flows` — 3 `integrity-check` steps: 01, 02 roots → 03 join (edges 01→03, 02→03), `defaultCategory` and every `wqmCategory` = `Default` | 201 |
| (a) | `POST /flows/{id}/validate` | 200 `{"errors":[],"warnings":[]}` |
| (a) | `POST /flows/{id}/dispatch` (no confirmations) | 202; 3 StepRuns with `guid`, `timeQueued` |
| (a) | `GET /runs/{guid}/events` (SSE) until `run-terminal` | 01, 02 `running` in parallel; 03 `queued` until both complete; all three `completed`; run `completed` |
| (b) | `POST /flows` — single `compact-globals` step on `Default` | 201 (saved flows stay loadable) |
| (b) | `POST /flows/{id}/validate` | 200, one `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` naming the step |
| (b) | `POST /flows/{id}/dispatch` | 422 with the same error; no run created |
| (c) | `POST /flows` — single `integrity-check` step, `wqmCategory: "NONEXISTENT"` | 201 |
| (c) | `POST /flows/{id}/validate` | 200, one `CATEGORY_NOT_FOUND` naming the step and `NONEXISTENT` |
| (c) | `POST /flows/{id}/dispatch` | 422 with the same error; no run created |

Block (a) must finish inside the 60 s token window (E-1): three integrity checks completed in
~30 s in T070.

## Evidence / notes (not acceptance)

Recorded when convenient; a mismatch here is a note, not a failure of 004.

- **Test suite count** after 004 (2026-09-23, `sentai-task-iris-1`): **105/105 methods passed**
  (86 pre-existing, one renamed, none deleted + 19 new), 0 failed.
- **HTTP run**: `IRIS_USER=… IRIS_PASSWORD=… python3 specs/004-backend-hardening/evidence/run_quickstart.py`
  executes the catalog check and blocks (a)–(c), writing `evidence/quickstart-http-<date>.json`.
- **Scheduling (D-2)**: `/schedule` validates the flow and registers a native task, but scheduled
  runs cannot authenticate to the platform in v1 and are not a supported execution path. Use
  manual dispatch.
- **Runs longer than 60 s (E-1)**: platform calls made after the access token expires return 401,
  stored verbatim as the step's failure reason.
- **Real WQM write**: covered by `WqmCategoryEndpointTest` (PUT contract). One manual
  `PUT /wqm/categories/Utility` with an unchanged value + read-back may be recorded here.
- **`defragment-globals`**: unavailable in v1; no probe in 004.
- **Destructive schedule refusal**: still enforced (`DESTRUCTIVE_NOT_SCHEDULABLE`), covered by
  `DestructiveSchedulingRuleTest`; no v1-available type is destructive.
- **Default category**: a flow created without categories gets `SENTAI.DEFAULT`, which does not
  exist on a stock instance → `CATEGORY_NOT_FOUND` at validation (spec Clarifications Q1).
- **Sanitation**: unchanged from spec 003 (`scripts/sanitation/`).

## Teardown

The product API has no flow delete; created flows and runs stay in `IRISAPP` (use distinct
flow names per run).
