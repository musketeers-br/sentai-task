# API Contract Delta — 004 Backend Hardening

Base: spec 002 [`openapi.yaml`](../../002-canvas-ui/contracts/openapi.yaml) as implemented in spec 003.
**No new endpoints. No removed endpoints. No request shape changes.** Only the deltas below.

## Product API (`/csp/sentai/api/v1`)

### `GET /catalog/step-types` — response item gains `available`

```json
{ "type": "compact-globals", "class": "%SYS.Task.CompactGlobals", "category": "storage",
  "destructive": false, "pausable": false, "available": false }
```

Additive field; existing consumers ignore it. The palette may grey out `available: false`.

### `POST /flows/{id}/validate` — two new error codes in `ValidationReport.errors[]`

```json
{"errors":[
  {"stepId":"05","code":"STEP_TYPE_NOT_SUPPORTED_ON_TARGET",
   "message":"Step type 'switch-journal' is not supported on the target platform in v1 (supported: integrity-check)"},
  {"stepId":"01","code":"CATEGORY_NOT_FOUND",
   "message":"WQM category 'NONEXISTENT' does not exist on the target platform"}
 ],"warnings":[]}
```

Status code unchanged (200 with the report).

### `POST /flows/{id}/dispatch`, `POST /flows/{id}/schedule`

Unchanged statuses: 422 with the same `ValidationReport` when either new code is present. An
unavailable destructive step yields 422, not 428. `schedule` may report both
`STEP_TYPE_NOT_SUPPORTED_ON_TARGET` and `DESTRUCTIVE_NOT_SCHEDULABLE` for the same step.

### `POST /runs/{runGuid}/steps/{stepGuid}/rerun`

New refusal on the existing 409 path:

```json
{"status":409,"title":"Conflict",
 "detail":"ERROR #5001: STEP_TYPE_NOT_SUPPORTED_ON_TARGET: step '04' type 'purge-audit-records' is not supported on the target platform in v1"}
```

No StepRun created, no platform call.

### `PUT /wqm/categories/{name}`

Request/response unchanged. Invariant accepts `0` in `maxWorkers`/`maxTotalWorkers` as unbounded
(see [data-model.md](../data-model.md)). A non-zero violation is still 422 before any platform call.

## Platform API consumed (IRIS 2026.2 `/api/admin`)

| Purpose | Before (spec 003) | After (spec 004) | Evidence |
|---|---|---|---|
| Category write | `POST /api/admin/v2/wqm-categories/<name>`, body incl. `Name` | `PUT /api/admin/v2/wqm-category?name=<url-encoded name>`, body without `Name`, numbers as JSON numbers, `AlwaysQueue` as boolean | spec 001 evidence 10a |
| Category list (now also at validation) | `GET /api/admin/v2/wqm-categories` | same; called once per validate/dispatch/schedule with the operator's credential | spec 001 evidence 09 |
