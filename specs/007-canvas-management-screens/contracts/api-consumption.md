# API Consumption Contract — 007 (frontend → `/csp/sentai/api/v1`)

The frontend calls only existing endpoints, through `src/lib/api/client.ts` `request()`. Every call
carries the signed-in operator's bearer token (`session.authorization()`), which is renewed
proactively and never cached beyond memory.

Shapes are defined by [spec 006 api-delta](../../006-task-catalog-api/contracts/api-delta.md) and
[spec 005 api-delta](../../005-declared-custom-steps/contracts/api-delta.md). This file fixes
**what the screen does with each answer**.

## Error value (extends the existing `ApiError`)

```ts
| { kind: 'problem'; status: number; title: string; detail: string;
    platformStatus?: { errors: Array<{ error: string }>; summary: string };   // passed through untouched
    platformInfo?: Record<string, unknown> }                                   // passed through untouched
```

**Refusal text** (one helper, unit-tested) is built in this order:
1. `detail` if it is non-empty;
2. otherwise the `platformStatus.errors[].error` values joined by "; ";
3. otherwise **"no reason given"**.

It is always shown as `HTTP <status> — <text>`. No paraphrase is added (Constitution III).

## Calls

### 1. `GET /catalog/tasks?q&namespace&filter&destructiveOnly` — catalog list (US-1, US-3)

| Answer | Screen |
|---|---|
| 200 `{total, matched, items}` | Rows in `orderByNextRun` order. "`matched` of `total` tasks". If the request had no filters, refresh the namespace options (research R-2) |
| 400 `INVALID_FILTER: …` | Refusal banner with the detail verbatim; the previous rows stay. The controls cannot produce this answer (spec edge case) |
| 401 | `session.expire()`, then the SignIn overlay (existing) |
| 403 (for example, no `%Admin_Task`) | Refused state (FR-010): "HTTP 403 — no reason given" on 2026.2, and **no rows** |
| 502 `PLATFORM_UNREACHABLE` | Refused state with the detail |
| Network error | Refused state with the message |

Parameters are omitted when at their default: `namespace` when *all*, `filter` when `all`,
`destructiveOnly` when off, and `q` when empty. `destructiveOnly` is sent as `1`.

### 2. `GET /catalog/tasks/{taskId}` — detail (US-1, US-2)

| Answer | Screen |
|---|---|
| 200 catalog task (+ `recentRuns` \| absent) | Detail pane. Recent runs follow data-model (absent / `[]` / list) |
| 404 `ERROR #5809…` | Detail shows "Task not found" plus the detail verbatim, and the row is kept (it may have been deleted since the list was read) |
| 403 / 502 / network | Detail refused state with the refusal text |

A non-numeric `task` query value is not requested: the detail shows "Task not found" with no call.

### 3. `POST /catalog/tasks/{taskId}/suspend` body `{"suspended": true|false}` (US-4)

| Answer | Screen |
|---|---|
| 200 re-read catalog task | Detail updated from the body, then the list is re-read (FR-011) |
| 403 `{errors:[],summary:""}` | Action error "HTTP 403 — no reason given". The shown state is unchanged, and the item is re-read |
| 404 | Action error with the detail verbatim |
| 502 `SUSPEND_NOT_APPLIED: …` | Action error with the detail verbatim. The item is re-read, so the state shown is the API's |
| 502 `PLATFORM_UNREACHABLE` / network | Action error, and the item is re-read |
| 401 | SignIn overlay. The action is **not** replayed automatically (research R-5) |

The button is disabled from send until an answer arrives. Exactly one of *Suspend* or *Resume* is
shown, chosen from `suspended`. When `suspended` is unavailable, **neither** is shown and the
reason is displayed instead.

### 4. `GET /catalog/step-types` — palette and inspector (US-5, US-6)

Read once at boot (existing). The new fields `label`, `executor` and `parameters` are mapped in
`fromWireStepTypes`. A catalog without them (pre-005) still works: no *Custom* group entries
other than legacy `custom`, and no generated form.

### 5. `POST /flows/{id}/validate`, `/dispatch`, `/schedule` — findings (US-5, US-6)

- The findings keep the shape `{stepId, code, message}`, plus an optional `parameter` when spec 005
  adds it (research R-4).
- `PARAM_*`, `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` and `IN_PROCESS_NOT_SCHEDULABLE` are shown and
  counted like every other finding. The status bar logic is unchanged.
- `/dispatch` now sends `confirmations: [{stepId, typedName}]` for destructive steps. A 428 shows
  the Problem `detail` verbatim in the dialog.

### 6. Unchanged calls

`GET/POST/PUT /flows…`, `/runs…` and `/wqm/categories` are unchanged. The live-run screen ignores
spec 005's `result` and `executedAs` (out of scope).

## Backend dependencies found by this plan (register in 005/006, do not work around)

| # | Spec | Need | Effect until provided |
|---|---|---|---|
| BD-1 | 005 | `parameter` field on `PARAM_REQUIRED`, `PARAM_TYPE_MISMATCH` and `PARAM_OUT_OF_RANGE` findings | Parameter errors are shown at step level, and SC-005's "on their field" part is unmet |
| BD-2 | 005 | Declare `purge-audit-records`' parameters in the catalog (or keep it unavailable forever) | The inspector keeps its local 002 field for that one type |
| BD-3 | 006 | Tasks T001–T005 deployed on the container | Part A e2e cannot run; unit tests use the api-delta fixtures |
| BD-4 | 005 | Tasks 1–5 deployed (catalog fields, validation codes) | Part B e2e cannot run |
