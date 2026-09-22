# Phase 1 — Data model (implementation)

Feature: `003-backend-objectscript` · Date: 2026-09-22

This file does **not** redefine `specs/002-canvas-ui/contracts/data-model.md` — it is the source
of truth for data shape and remains so. This file only adds what a real implementation needs and
that the 002 contract, purposely, left as an "implementation detail": namespace/database, indexes,
non-persistent service classes, and the step-type registry as compiled data. No field, type, or
rule below contradicts `002-canvas-ui`.

## Namespace and databases

Reuses the `IRISAPP` namespace and the `IRISAPP_DATA`/`IRISAPP_CODE` databases already provisioned
by `merge.cpf` and `iris.script` (see repository root) — no new namespace, database, or resource is
created by this plan. Root package: `sentai`.

## Persistent classes (`sentai.model.*`)

All `%Persistent` + `%JSON.Adaptor`, living in the `IRISAPP_DATA` database.

| Class | Fields (beyond those already listed in `002-canvas-ui/contracts/data-model.md`) | Indexes |
|---|---|---|
| `sentai.model.Flow` | — (fields identical to the contract: `id`, `name`, `revision`, `savedAt`, `savedBy`, `defaultCategory`, `scheduleSpec`, `canvasGeometry`) | Unique case-insensitive index on `name` (supports FR-005) |
| `sentai.model.Step` | — (identical to the contract) | Index on `(flow, id)` — logical key within the flow |
| `sentai.model.Edge` | — (identical to the contract) | Index on `(flow, target)` — supports wave-eligibility computation (R-006) and cycle detection (R-008) without scanning every edge of the flow on each check |
| `sentai.model.Join` | — (identical to the contract) | Unique index on `(flow, target)` — at most one join entry per target step |
| `sentai.model.Run` | + `eventVersion` (`%Integer`, starts at 0, incremented on every observable change — used by SSE in R-010) | Index on `flow` (supports `GET /runs?flowId=`) |
| `sentai.model.StepRun` | — (identical to the contract) | Index on `(run, stepId)` |
| `sentai.model.Category` | — (identical to the contract) | Unique index on `name` |
| `sentai.model.LogEntry` | `run` (ref Run), `at`, `stepId` (nullable), `severity`, `message` — shape of `openapi.yaml`'s `LogEntry` | Index on `(run, at)` — "most recent first" read order (FR-033 of 002, reused here for `RunDetail.log`) |

`eventVersion` and `sentai.model.LogEntry` are the only two field/class additions this plan makes
on top of the `002-canvas-ui` contract — both exist solely to support FR-025/FR-026 (event
publication) without duplicating what `openapi.yaml`'s schemas (`Run`, `RunDetail`, `LogEntry`)
already anticipate; `eventVersion` is internal, never serialized in the REST response.

## Registry global (`^sentaiRun`)

Shape identical to the one already contracted in `002-canvas-ui/contracts/data-model.md` (see
`research.md` R-004) — reproduced here only for cross-reference, not redefined.

## Service classes (non-persistent)

No data table of their own — behavior, not state. Documented here because they make up
"persistence" in the broad sense of where each backend responsibility lives.

| Class | Responsibility |
|---|---|
| `sentai.rest.Dispatcher` | HTTP routing, authentication (`OnPreDispatch`), (de)serialization, error-to-status-code mapping |
| `sentai.validation.FlowValidator` | Every rule from `data-model.md §Validation rules` (002) plus the fixed precondition check |
| `sentai.dispatch.WaveDispatcher` | Wave eligibility, `%SYS.WorkQueueMgr` enqueueing, tracking via the administrative API, `StepRun` transitions |
| `sentai.registry.StepType` | Closed, declared catalog (`XData`) of the seven step types — see `data-model.md §Step types` of 002, reproduced unchanged |
| `sentai.wqm.CategoryService` | Category read/write via passthrough to the administrative API (`/api/admin/v2/wqm-categories`), plus computing `affectedTaskCount` and the nesting invariant |
| `sentai.catalog.TaskService` | Read access to the catalog of tasks already scheduled on the instance (P3, reducible) |

## Step-type registry — `XData` shape

Reproduction of the catalog already closed in `002-canvas-ui/contracts/data-model.md §Step types`,
as compiled data (not code):

```json
[
  { "type": "integrity-check",       "class": "%SYS.Task.IntegrityCheck",     "category": "verification", "destructive": false, "pausable": false },
  { "type": "compact-globals",       "class": "%SYS.Task.CompactGlobals",     "category": "storage",      "destructive": false, "pausable": false },
  { "type": "defragment-globals",    "class": "%SYS.Task.Defragment",         "category": "storage",      "destructive": false, "pausable": false },
  { "type": "switch-journal",        "class": "%SYS.Task.SwitchJournal",      "category": "journal",      "destructive": false, "pausable": false },
  { "type": "purge-audit-records",   "class": "%SYS.Task.PurgeAuditDatabase", "category": "purge",        "destructive": true,  "pausable": true  },
  { "type": "purge-task-history",    "class": "%SYS.Task.PurgeTaskHistory",   "category": "purge",        "destructive": true,  "pausable": true  },
  { "type": "custom",                "class": null,                          "category": "custom",       "destructive": "declared by subclass", "pausable": "declared by subclass" }
]
```

`pausable = true` only for `purge-audit-records` and `purge-task-history` — the direct
implementation of the fixed decision "Pause: purge family only in v1".

## State machine — implementation

Identical to the one in `002-canvas-ui/contracts/data-model.md` (reproduced, not changed):

```
queued ──► running ──► completed
  │           │
  │           ├──────► failed
  │           ├──────► paused ──► running
  │           └──────► cancelled
  └──────────────────► cancelled
```

Implemented as a `sentai.model.StepRun:TransitionTo(newState, ...)` method that validates the
transition against a static transition table before writing — never a direct `%Save()` of `state`
from any caller — so that no code path can produce an illegal transition (`completed → *`,
`failed → *`, `cancelled → *`, `queued → running` without a GUID, `queued → paused`).

## Requirements → entities/classes mapping

| Requirement(s) | Primary entity/class |
|---|---|
| FR-001–FR-011 | `sentai.model.Flow/Step/Edge/Join`, `sentai.registry.StepType` |
| FR-012–FR-015 | `sentai.validation.FlowValidator` |
| FR-016–FR-024 | `sentai.model.Run/StepRun`, `sentai.dispatch.WaveDispatcher`, `^sentaiRun` |
| FR-025–FR-026 | `sentai.model.Run.eventVersion`, `sentai.model.LogEntry`, `sentai.rest.Dispatcher` (SSE method) |
| FR-027–FR-030 | `sentai.dispatch.WaveDispatcher` (run/step control) |
| FR-031–FR-032 | `sentai.rest.Dispatcher` (schedule) via the native administrative API |
| FR-033–FR-036 | `sentai.wqm.CategoryService` |
| FR-037–FR-039 | `sentai.registry.StepType`, `sentai.catalog.TaskService` |
| FR-040–FR-043 | `sentai.rest.Dispatcher.OnPreDispatch`, `^sentaiRun` |
