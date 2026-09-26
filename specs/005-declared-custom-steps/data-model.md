# Data Model — 005 Declared Custom Steps

No change to the flow document schema. Additive changes only: catalog entries (code) and two
`StepRun` properties (run data).

## Declared step type (catalog entry, `XData Catalog` in `sentai.registry.StepType`)

| Field | Type | Notes |
|---|---|---|
| `type` | string | Unique; the ONLY thing a step contributes to selecting code |
| `label` | string | Human name for the palette (spec 007) |
| `class` | string | Platform class that implements the work; read from the catalog only |
| `category` | string | verification / storage / journal / purge / custom |
| `executor` | `platform-api` \| `in-process` | **new**; `integrity-check` stays `platform-api` |
| `destructive` | boolean | unchanged semantics (typed confirmation, not schedulable) |
| `pausable` | boolean | `false` for every in-process type |
| `available` | boolean | spec 004 semantics; `true` only after real-instance proof |
| `parameters` | array | **new**; present for in-process types and for `purge-audit-records` (spec 007 BD-2, declaration only: that type stays `platform-api` and unavailable) |

### Parameter definition (`parameters[]`)

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Key in the step's `parameters` object |
| `property` | string | yes | Property of the declared class that receives the value (catalog-owned) |
| `type` | `string`\|`integer`\|`number`\|`boolean` | yes | |
| `required` | boolean | yes | |
| `default` | per `type` | no | Applied when the key is absent |
| `min` / `max` | number | no | Only for `integer`/`number` |
| `description` | string | yes | Shown by the canvas (spec 007) |

### Entries after this spec

| type | executor | class | destructive | available | parameters |
|---|---|---|---|---|---|
| integrity-check | platform-api | %SYS.Task.IntegrityCheck | false | true | — |
| storage-headroom-check | in-process | sentai.steps.StorageHeadroomCheck | false | true* | `minFreePercent` number 0–100, default 10 |
| db-size-report | in-process | sentai.steps.DatabaseSizeReport | false | true* | — |
| switch-journal | in-process | %SYS.Task.SwitchJournal | false | true* | — |
| purge-task-history | in-process | %SYS.Task.PurgeTaskHistory | **true** | true* | `keepDays` integer ≥ 0, default 30 → `KeepDays` |
| compact-globals, defragment-globals | platform-api | unchanged | unchanged | false | — |
| purge-audit-records | platform-api | %SYS.Task.PurgeAudit (spec 006 D-4) | true | false | `daysToKeep` integer ≥ 1, required, no default → `KeepDays` (BD-2) |
| custom (legacy) | — | "" | false | false | — (never executes) |

\* `true` only after the quickstart evidence for that type is recorded (FR-007).

## StepRun (persistent) — two additive properties

| Property | Type | Notes |
|---|---|---|
| `result` | `%String(MAXLEN = 8000)` | **new**; JSON text; written only by the in-process worker from the task's `Result`; empty otherwise. Exposed as `result` (parsed object) in `GET /runs/{guid}` → `steps[]` |
| `executedAs` | `%String(MAXLEN = 160)` | **new**; `$USERNAME` of the worker that ran an in-process step (evidence for SC-006); empty for `platform-api` steps. Exposed as `executedAs` |

### Result size rule

`result` holds at most 8000 characters of JSON. When the task's result is larger, the executor
drops elements from the **end of the largest top-level array** until it fits and adds
`"truncated": true, "omitted": <n>`. If it still does not fit, it stores
`{"truncated": true, "originalLength": <n>}`. The stored value is always valid JSON.

### Terminal writes are locked

`StepRun.TransitionLocked(guid, state, reason)` opens the StepRun with exclusive concurrency
(`%OpenId(id, 4)` — lock + fresh read), applies `IsLegalTransition`, saves and releases. Both the
worker (completion) and the loop (timeout sweep) use it, so exactly one terminal state wins; a
loser gets `SentaiIllegalTransition` and records nothing. Lock timeout: the loop retries on its
next pass; the worker retries 3× and then gives up (the loop's timeout still ends the step).

### Namespace frame

The worker's entry (`Run(guid)`, namespace `IRISAPP`) builds the task, then calls a separate frame
that does `New $NAMESPACE`, sets the declared properties and calls `OnTask` inside `Try/Catch`,
returning plain values. Every persistent write (`result`, `executedAs`, terminal transition)
happens after that frame returns, back in `IRISAPP` — native tasks switch to `%SYS` (R-5).

### State transitions for an in-process step

```
queued ──(loop: StartStep)──▶ running ──(worker: OnTask OK)────────▶ completed
                                 │     ──(worker: error %Status)───▶ failed  reason = status text
                                 │     ──(worker: exception)───────▶ failed  reason = ex.DisplayString()
                                 └──(loop: now − timeStarted > timeout)▶ failed  reason = "timed out after N min"
```

- The loop sets `running` **before** queueing, so the next loop pass never re-enqueues the step.
- Timeout = `step.timeoutMinutes`, or 60 when 0. It counts from `running`, i.e. **including the
  time spent waiting for a worker** under the category's ceilings (a step that never gets a
  worker still ends).
- Every terminal transition goes through `TransitionLocked` (see above).
- Events: each transition bumps the run's `eventVersion` (existing, row-level SQL, in the writing
  process); the event stream re-reads it, so worker-written transitions are streamed like any other.
- Terminal → terminal is refused by `IsLegalTransition` (existing), so a late worker result after a
  timeout is discarded.
- Cancel stays local (F-2): the step becomes `cancelled`; the work may finish in the background and
  its late transition is discarded the same way.
- Join, wave and run-finalization rules are unchanged.

## Validation codes (existing `{stepId, code, message}` shape)

| Code | When | Message names |
|---|---|---|
| `PARAM_REQUIRED` | required parameter absent | step, parameter |
| `PARAM_TYPE_MISMATCH` | value not of the declared type | step, parameter, expected type |
| `PARAM_OUT_OF_RANGE` | number outside `min`/`max` | step, parameter, bounds |
| `PARAM_UNKNOWN` | key not in the schema | step, parameter |
| `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` *(reused)* | type unavailable, **or** its catalog class not compiled / not a task definition | step, type |
| `IN_PROCESS_NOT_SCHEDULABLE` | `/schedule` only: the flow has an in-process step (no operator identity at fire time) | step, type |

Schema checks apply only to types that declare `parameters`.

## Identity rules (request-level refusals, not validation codes)

| HTTP | Code | When |
|---|---|---|
| 403 | `RUN_CREDENTIAL_USER_MISMATCH` | `/dispatch` with a `runCredential` whose redeemed pair belongs to a user other than the requester; no run is created |
| 403 | `RERUN_NOT_BY_DISPATCHER` | `/rerun` requested by a user other than `run.dispatchedBy` |

A run therefore has one identity: the dispatcher's. In-process steps run as that user (R-1,
recorded in `executedAs`); management-API steps use that user's run credential.

## Result shapes (shipped types)

- `db-size-report`: `{"databases":[{"name":"IRISAPP_DATA","directory":"…","sizeMB":…,"freeMB":…}]}`
- `storage-headroom-check`: `{"minFreePercent":10,"locations":[{"path":"…","freePercent":93.7,"ok":true}]}`;
  on failure the failure reason lists each location below the threshold and by how much.
