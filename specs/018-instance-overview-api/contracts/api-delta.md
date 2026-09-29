# API delta: Instance Overview

All routes under `/csp/sentai/api/v1`, Bearer token as every other route (FR-017), JSON. Refusals
use the existing problem shape `{status, title, detail}`; platform refusals add
`platformStatus` verbatim (spec 006 pattern). Shapes: [data-model.md](../data-model.md).

Any `target` in the query string or body of these routes → `400 OVERVIEW_PRIMARY_ONLY`, no platform
call (FR-018).

## `GET /overview` — summary (US2)

`200` → `Summary` (data-model §3), always 11 entries. Per-area failures are inside the entries.

```json
{
  "readAt": "2026-09-29T20:10:00Z",
  "areas": [
    {"area": "processes", "group": "instance", "outcome": "ok", "readAt": "…",
     "headline": {"count": 65, "busiest": {"Pid": 3944, "Routine": "…", "Commands": 1394911}},
     "problem": null, "stepType": null},
    {"area": "security", "group": "report", "outcome": "refused", "readAt": "…", "headline": null,
     "problem": {"title": "Forbidden", "detail": "…", "httpStatus": 403, "platformStatus": {"errors": [], "summary": "…"}},
     "stepType": "security-posture-report"}
  ]
}
```

## `GET /overview/readings/{area}` — one reading (US1)

`area` ∈ `processes | locks | memory | activity | devices | licenses | web-sessions`.

- `200` → `Reading` (data-model §2)
- `404` `UNKNOWN_READING` — any other value, including report areas, paths or anything with `/`
- platform refusal → the platform's HTTP status (`502` when it answered < 400 with errors) and
  `platformStatus` verbatim; platform silent → `502 PLATFORM_UNREACHABLE`

## `POST /overview/reports/{stepType}` — on-demand report (US3)

Body `{"parameters": {…}}` optional. `stepType` must be a catalog type with executor
`platform-read`.

- `200` → `OnDemandReport` (data-model §4) — also when `state` is `failed` (a refused read is a
  failed report, as in a run)
- `404` `UNKNOWN_STEP_TYPE` / `422` `STEP_TYPE_NOT_A_REPORT` — without a platform call
- `422` → `{errors, warnings}` with the validator's `PARAM_*` codes
- Creates no run: `GET /runs` is unchanged.

## `POST /overview/areas/{area}/flow` — area → flow (US4)

Body `{"parameters": {…}}` optional.

- `201` → `{flow, validation}` (data-model §6)
- `404` `UNKNOWN_AREA`; `409` `AREA_HAS_NO_STEP_TYPE`
- `422` → parameter errors as above, nothing created

The flow is then scheduled with the existing `POST /flows/{id}/schedule`, unchanged.

## Process actions (US5 — only if the spike passes, FR-020)

`POST /overview/processes/{pid}/suspend`, `…/resume`, `…/terminate`

- Body for terminate: `{"confirmation": "<pid>"}`; missing or different →
  `428 CONFIRMATION_REQUIRED`, no platform call, no record
- Otherwise the platform's answer: `200` →
  `{"pid", "action", "platform": {"httpStatus", "status"}, "process": <re-read row or null>}`;
  a refusal → its HTTP status with `platformStatus` verbatim
- Every call that reached the platform writes one `ProcessAction` (data-model §5)

`GET /overview/process-actions?limit=1..200` (default 50) → `[ProcessAction]`, newest first.

The platform request body for each action is fixed by the spike's evidence and recorded here when
it lands.

## `openapi.yaml`

`specs/002-canvas-ui/contracts/openapi.yaml` gains the routes above and the schemas `Summary`,
`AreaEntry`, `Reading`, `OnDemandReport`, `ProcessAction`.
