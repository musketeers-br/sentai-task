# Data Model — 006 Task Catalog API

This feature adds no persistence and does not change the flow schema. The catalog task is a **view**
assembled for each request from the platform's reads (research R-1) plus the product's own flows.
Nothing about it is cached across requests (Constitution III).

## Catalog task

A field is present only when a platform read delivered it. A read that failed leaves its fields
absent and adds an `unavailable` entry for them (FR-009). No field is ever given a default.

| Field | Type | Source (platform read → key) | Notes |
|---|---|---|---|
| `taskId` | integer | list → `Id` (item read: the requested id) | The name `taskId` is kept from the current contract |
| `name` | string | list → `Name` (item read: single → `Name`) | |
| `namespace` | string | list → `Namespace` (item read: single → `NameSpace`) | |
| `class` | string | single → `TaskClass` | Replaces `className` (FR-001) |
| `runAsUser` | string | single → `RunAsUser` | FR-002 |
| `timePeriod` | string | single → `TimePeriod` | **Additive**. Values such as `"Daily"`, `"Weekly"`, `"Run After"`, exactly as sent. This is how a run-after task is shown (R-5) |
| `nextRun` | string | info → `NextScheduled` | Verbatim. `""` when the platform has none (run-after, or none computed). A suspended task **keeps** its value (R-3) |
| `lastStarted` | string | info → `LastStarted` | Verbatim, `""` when never |
| `lastFinished` | string | info → `LastFinished` | Verbatim. `lastRun` is kept as an alias (it came from the list) |
| `status` | string | info → `Status` | `"1"` passed through. A serialized `%Status` becomes the platform's own text for it (`GetErrorText`), which R-4/R-5 proved equals the history `Status` and the portal's `DisplayStatus`. Anything else is passed through unchanged |
| `lastError` | string | info → `Error` | **Verbatim**. The platform writes `"Success"` after a successful run and `""` after a failed one (the failure text is in `status`) |
| `suspended` | boolean | info → `Suspended` | Now comes from **info**. The list value is always `false` (R-1) |
| `destructive` | boolean | derived (below) | `isDestructive` is kept as an alias |
| `destructiveUnknown` | boolean | derived (below) | `true` only when `destructive` could not be derived |
| `origin` | object \| absent | derived from `name` (below) | Present only when the grammar matches |
| `unavailable` | array \| absent | per-task read failures | Present only when a per-task read failed |
| `recentRuns` | array \| absent | history → rows | **Item read only** (FR-008, R-4) |

**Removed** (the only two false values FR-010 names): `state`, which was invented
(`cancelled`/`queued`), and `className`, which was the list's `Type`.

**Kept as aliases carrying corrected values** (FR-010 permits no other removal):

- `isDestructive` = `destructive`;
- `lastRun` = `lastFinished` (now from info, not from the lossy list).

Both are marked deprecated in the OpenAPI and can be dropped once spec 007 consumes the new names.
Replacements are listed in [contracts/api-delta.md](contracts/api-delta.md).

### `unavailable[]`: partial reads (FR-009)

Each entry describes one per-task read that did not return 200:

```json
{ "read": "info", "fields": ["nextRun","lastStarted","lastFinished","status","lastError","suspended"],
  "httpStatus": 404, "platformStatus": { "errors": [ … verbatim … ], "summary": "…" } }
```

- `read` is `single`, `info` or `history` (history applies to the item read only).
- `fields` lists the catalog fields that read would have supplied. A failed single read also
  removes `class`, so destructiveness then falls back to its unknown case (below).
- `platformStatus` is the platform's `status` object, **verbatim**. For a 403 the platform gives
  `{"errors":[],"summary":""}`: it states no reason, and the product adds none.
- A failed **list** read is not partial. The whole call is refused (see
  [contracts/api-delta.md](contracts/api-delta.md) §Errors).

The user's draft shape was a single `{fields[], reason}` object. We use an array because the two
per-task reads (single and info) can fail independently with different platform statuses, and
merging them would lose information (Constitution III).

## Destructiveness (FR-004)

These rules are evaluated in order. The step-type catalog (`sentai.registry.StepType`, whose sole
reader is `GetCatalog()`) remains the only source.

1. **`class` unavailable** → `destructive:false, destructiveUnknown:true`.
2. **The class is a catalog entry's `class`** (entries with a non-empty class, including the types
   spec 005 adds) → `destructive` = that entry's `destructive`, `destructiveUnknown:false`.
3. **`class` = `sentai.dispatch.ScheduledFlowTask`** (the product's own scheduled task), `origin`
   present, and the step `origin.stepId` of flow `origin.flowId` exists →
   `destructive = StepType.IsDestructive(step.type)`, `destructiveUnknown:false`. This is the
   product's own record of what that task runs, so the value is known rather than guessed.
   Scheduling refuses destructive flows (spec 003 TD-06), so this is normally `false`, but it is
   read and not assumed.
4. **Anything else** (a platform class the catalog does not name, or a `ScheduledFlowTask` whose
   flow or step no longer exists) → `destructive:false, destructiveUnknown:true`.

New helper: `StepType.DestructiveByClass(class, .known) As %Boolean`. Matching is exact and
case-sensitive, like platform class names. Matching is on the catalog entry's `class`, never on
`type`.

## SentaiTask origin (FR-005)

**Grammar** (anchored, applied to the platform's `name` exactly as sent):

```
^SentaiTask: ([1-9][0-9]*)#([0-9A-Za-z_-]{1,8})$
```

The grammar is derived from the generator (`Dispatcher.CreateNativeTask`:
`"SentaiTask: "_flowId_"#"_stepId`), where `flowId` is the Flow `%ID` (a positive integer without
leading zeros) and `stepId` follows the flow schema's `stepId` pattern `^[0-9A-Za-z_-]{1,8}$`.

The draft grammar used `(\d+)#(\d{2,})`. We do not adopt it, because it would drop the origin
from real product tasks whose step id is valid but not two or more digits (for example `7` or
`a1`), and it would accept step ids longer than 8, which the product never generates.

Anything else produces no `origin`. That includes prefix-only matches (`SentaiTask: 1#01 copy`,
`SentaiTask:1#01`, `sentaitask: 1#01`, `SentaiTask: 01#01`, `SentaiTask: 1#`, and step ids of 9
or more characters).

In ObjectScript the regex runs through `$MATCH` (a platform function over data). This is not code
evaluation.

```json
"origin": { "flowId": "1", "stepId": "01", "flowExists": true }
```

- `flowId` and `stepId` are strings exactly as captured (`stepId` keeps `"01"`). `flowId` is a
  string for the same reason.
- `flowExists` is `##class(sentai.model.Flow).%ExistsId(flowId)`, evaluated on every request. A
  deleted flow keeps its `origin` with `flowExists:false` (US-2 scenario 3).
- The step lookup for destructiveness is a parameterized statement:
  `SELECT type FROM sentai_model.Step WHERE flow = ? AND id = ?`.

## Filters and count (FR-007)

Query parameters are unchanged in name: `q`, `namespace`, `filter`, `destructiveOnly`. All of
them are **data**. They are compared in memory with the corrected values. No SQL is built from
them, and there is no platform-side filter.

| Filter | Keeps a task when | Unknown or unavailable value |
|---|---|---|
| `q` (text) | the lowercased `q` is a substring of the lowercased `name` **or** `class` | if `class` is unavailable, only `name` is matched |
| `namespace` | `namespace` equals the parameter, case-insensitively | — |
| `filter=scheduled` | `suspended = false` (the platform's info value) | `suspended` unavailable → **excluded** |
| `filter=suspended` | `suspended = true` | `suspended` unavailable → **excluded** |
| `filter=all` (default) | always | — |
| `destructiveOnly=1` | `destructive = true` | `destructiveUnknown` tasks are **excluded** (recommendation adopted) |

- "Scheduled" means "not suspended" according to the platform. It does not mean "has a next run",
  because a suspended task keeps `NextScheduled` (R-3).
- `filter` values outside `all|scheduled|suspended` → **400** Problem `INVALID_FILTER`. Today such
  a value silently acts as `all`. `destructiveOnly` accepts `0|1|true|false`, and any other value
  → **400** `INVALID_FILTER`.
- Combined filters are ANDed.

**Count "N of M"**: the current response is already the envelope `{ total, matched, items }`, so
`matched` = N and `total` = M. The format does not change. `total` = the number of tasks the
platform's list returned (including tasks with partial reads), and `matched` = `items.length`.

## Recent run (item read only, FR-008)

`recentRuns` holds up to 5 rows, newest first, from `GET /api/admin/v2/task/history?taskId=<id>`,
restricted to rows whose `Routine` equals the task's `class` (execution rows; admin events carry
`TASKMGR`, R-4). Each row keeps the platform's own keys and values:

```json
{ "LastStart": "2026-09-26 01:31:00", "Completed": "2026-09-26 01:31:00",
  "Status": "ERROR #5001: …", "Result": "", "Username": "…", "LogDatetime": "2026-09-26 01:31:00" }
```

No duration is computed, because the platform's precision is minutes. If `class` is unavailable,
execution rows cannot be told apart from admin events, so `recentRuns` is absent and flagged in
`unavailable` with `read:"history"`, `fields:["recentRuns"]`, the single read's HTTP status and
its `platformStatus`.

## Suspend / resume (FR-006): state change of a platform task

```
request {suspended:true}  → POST /api/admin/v2/task/suspend?id=<id> body {}  ─┐
request {suspended:false} → POST /api/admin/v2/task/resume?id=<id>  body {}  ─┤
                                                                              ├─ non-2xx → refusal verbatim, no re-read
                                                                              └─ 2xx → re-read single + info
                                                  info.Suspended = requested → 200 + catalog task (re-read)
                                                  info.Suspended ≠ requested → 502 SUSPEND_NOT_APPLIED + info verbatim
```

Both calls are idempotent on the platform: suspending a suspended task, or resuming a resumed one,
returns 200 (R-3). The product changes nothing else. There is no create, edit, delete, run-now or
schedule change (spec 004 D-2).
