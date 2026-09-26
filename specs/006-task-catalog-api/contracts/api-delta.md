# API Contract Delta — 006 Task Catalog API

Base: spec 002 [`openapi.yaml`](../../002-canvas-ui/contracts/openapi.yaml) (`CatalogTask`,
`CatalogTaskDetail`), as implemented in specs 003/004.

This feature adds **no new endpoints** and removes none. The request shapes do not change.

New responses:
- `400 INVALID_FILTER` for an invalid `filter` or `destructiveOnly`.
- `400` for a non-boolean `suspended`.
- `404` for a non-integer `taskId`, with no platform call.
- `502 SUSPEND_NOT_APPLIED` and `502 PLATFORM_UNREACHABLE`.
- A suspend `200` body that carries the re-read catalog task.

See §Errors and the suspend table below.

## Product API (`/csp/sentai/api/v1`)

### `GET /catalog/tasks` — list

The envelope is unchanged: `{ "total": M, "matched": N, "items": [CatalogTask…] }`. `total` counts
every task on the platform's list, and `matched` counts `items`.

Item before (spec 003/004):

```json
{ "taskId": 4, "name": "Integrity Check", "className": "System", "namespace": "%SYS",
  "nextRun": "2026-09-28 02:00:00", "lastRun": "", "state": "queued", "runAsUser": "",
  "isDestructive": false, "suspended": false }
```

Item after, using real values from task 4 on the dev instance (research R-1). The task is
suspended on the instance, although the old list reported it as `false`:

```json
{ "taskId": 4, "name": "Integrity Check", "namespace": "%SYS",
  "class": "%SYS.Task.IntegrityCheck", "runAsUser": "_SYSTEM", "timePeriod": "Weekly",
  "nextRun": "2026-09-28 02:00:00", "lastStarted": "", "lastFinished": "",
  "status": "1", "lastError": "", "suspended": true,
  "destructive": false, "destructiveUnknown": false,
  "isDestructive": false, "lastRun": "" }
```

A SentaiTask task, using real values from task 1000 of the 2026-09-25 case:

```json
{ "taskId": 1000, "name": "SentaiTask: 1#01", "namespace": "IRISAPP",
  "class": "sentai.dispatch.ScheduledFlowTask", "runAsUser": "_SYSTEM", "timePeriod": "Daily",
  "nextRun": "2026-09-27 00:00:00", "lastStarted": "2026-09-26 00:00:01",
  "lastFinished": "2026-09-26 00:00:01", "status": "1", "lastError": "Success",
  "suspended": false, "destructive": false, "destructiveUnknown": false,
  "isDestructive": false, "lastRun": "2026-09-26 00:00:01",
  "origin": { "flowId": "1", "stepId": "01", "flowExists": true } }
```

The task 1000 values were read from the platform object on 2026-09-26. The quickstart (a) evidence
replaces them with the product's own output.

A task whose info read failed (for example, it was deleted between the list read and its info read):

```json
{ "taskId": 1003, "name": "…", "namespace": "IRISAPP", "class": "…", "runAsUser": "…",
  "timePeriod": "Daily", "destructive": false, "destructiveUnknown": true,
  "unavailable": [ { "read": "info",
    "fields": ["nextRun","lastStarted","lastFinished","status","lastError","suspended"],
    "httpStatus": 404,
    "platformStatus": { "errors": [ { "error": "ERROR #5809: Object to Load not found, class '%SYS.Task', ID '1003'", "code": 5809, "domain": "%ObjectErrors", "id": "LoadObjectNotFound", "params": ["%SYS.Task","1003"] } ],
                        "summary": "ERROR #5809: Object to Load not found, class &#39;%SYS.Task&#39;, ID &#39;1003&#39;" } } ] }
```

#### Field changes

| Before | After | Why |
|---|---|---|
| `className` (= list `Type`, e.g. `"System"`) | **removed** → `class` (single `TaskClass`) | The old value was not a class (FR-001) |
| `state` (`suspended ? "cancelled" : "queued"`) | **removed** → `status` + `lastError` + `lastStarted` + `lastFinished` (info) | The old value was invented (FR-003) |
| `runAsUser` (always `""`) | `runAsUser` (single `RunAsUser`) | Same name, real value (FR-002) |
| `isDestructive` (always `false`) | kept, **deprecated alias** = `destructive`; new `destructive` + `destructiveUnknown` | Corrected value. FR-010 permits removing only `state` and `className` |
| `lastRun` (list `LastFinished`, truncated to minutes) | kept, **deprecated alias** = `lastFinished` (info) | Corrected source, name kept |
| `nextRun` (list, truncated to minutes; `"Runs After #1:00"`) | `nextRun` (info `NextScheduled`, verbatim, `""` when none) | The list value is an artefact (R-1) |
| `suspended` (list, always `false`) | `suspended` (info) | The list value is lossy (R-1) |
| — | `timePeriod`, `origin`, `unavailable` | Additive |

**Only `state` and `className` are removed (FR-010).** `CatalogTaskDetail.wqmCategory`,
`privilege` and `currentRunGuid` were never returned and still are not. `lastRuns` is replaced by
`recentRuns`, shown below.

#### Query parameters

These are unchanged in name: `q`, `namespace`, `filter` (`all` \| `scheduled` \| `suspended`) and
`destructiveOnly` (`0|1|true|false`). Their semantics are defined in
[data-model.md §Filters](../data-model.md#filters-and-count-fr-007). **New:** any other value of
`filter` or `destructiveOnly` → `400` `{"status":400,"title":"Bad Request","detail":"INVALID_FILTER: …"}`.

### `GET /catalog/tasks/{taskId}` — item read

Before, this endpoint re-listed every task and scanned for the id, and it answered 404
`"Task '<id>' does not exist"`. After, it makes one single read, one info read and one history
read. The response is the same catalog task as in the list, plus `recentRuns`:

```json
{ …catalog task…,
  "recentRuns": [
    { "LastStart": "2026-09-26 00:00:00", "Completed": "2026-09-26 00:00:00", "Status": "1",
      "Result": "Success", "Username": "_SYSTEM", "LogDatetime": "2026-09-26 00:00:01" } ] }
```

The example row above is task 1's real history row (R-4). `recentRuns` holds at most 5 execution
rows and is `[]` when there are none. It is absent (and flagged in `unavailable`) when the history
read fails or `class` is unavailable.

- A `taskId` that is not a positive integer → **404** with no platform call.
- The platform single read returns 404 → **404**
  `{"status":404,"title":"Not Found","detail":"ERROR #5809: …","platformStatus":{…verbatim…}}`.

### `POST /catalog/tasks/{taskId}/suspend` — suspend / resume

The request is unchanged: `{"suspended": true|false}`. When the body is absent, the value
defaults to `true`, as today. A non-boolean value → **400**.

| Case | Before | After |
|---|---|---|
| Platform call | `POST /api/admin/v2/tasks/<id>/suspend` `{"suspended":…}` → **404 on 2026.2** (R-3) | `POST /api/admin/v2/task/suspend?id=<id>` or `…/task/resume?id=<id>`, body `{}` |
| Success | `200 {}` | `200` + the **re-read** catalog task (additive body), with `suspended` equal to the platform's info value after the call |
| Platform 2xx but the state did not change | not detected | `502 {"status":502,"title":"Bad Gateway","detail":"SUSPEND_NOT_APPLIED: the platform accepted the call but reports suspended=<v>","platformInfo":{…info result verbatim…}}` |
| Operator lacks the privilege | `500 "SentaiAdminApiError: … HTTP 403"` | `403 {"status":403,"title":"Forbidden","detail":"","platformStatus":{"errors":[],"summary":""}}`. `detail` is the platform's error text, which is empty on 2026.2. Nothing is added |
| Unknown task | `500` | `404 {"status":404,"title":"Not Found","detail":"ERROR #5809: Object to Load not found, class '%SYS.Task', ID '99999'","platformStatus":{…}}` |

The "not supported on target" error of FR-006 is **not** introduced, because the contract is proven
(R-3).

### Errors (all three calls)

| Condition | Product answer |
|---|---|
| Platform refuses the **list** read (for example 403) | Same HTTP status. Problem with `detail` = the platform's `errors[].error` joined by `"; "` (`""` if none), plus `platformStatus` verbatim. Items are not returned |
| A per-task read fails inside the list | 200. The task is kept with `unavailable[]` (FR-009) |
| Platform unreachable (no HTTP status) | `502` Problem `PLATFORM_UNREACHABLE` |
| Invalid filter | `400` `INVALID_FILTER` |

`platformStatus` / `platformInfo` are **additive** members of the existing Problem object
`{status,title,detail}`.

## Platform API consumed (IRIS 2026.2 `/api/admin`)

| Purpose | Before | After | Evidence |
|---|---|---|---|
| Enumerate tasks | `GET /v2/tasks` (and all fields taken from it) | `GET /v2/tasks`, used only for `Id`, `Name`, `Namespace` | R-1, spec 001 ev. 03 |
| Class, run-as user, period | — | `GET /v2/task?id=<id>` | R-1, spec 001 ev. 04 |
| Status, error, times, suspended | — | `GET /v2/task/info?id=<id>` | R-1, spec 001 ev. 05 |
| History | — | `GET /v2/task/history?taskId=<id>` (item read only) | R-4 |
| Suspend | `POST /v2/tasks/<id>/suspend` (404) | `POST /v2/task/suspend?id=<id>`, JSON body `{}` | R-3 |
| Resume | same wrong path | `POST /v2/task/resume?id=<id>`, JSON body `{}` | R-3 |

Every call uses the requesting operator's bearer token. Reads need `%Admin_Task` (403 without any
task privilege). Suspend and resume need `%Admin_Task`.

## OpenAPI

`specs/002-canvas-ui/contracts/openapi.yaml` `CatalogTask` / `CatalogTaskDetail` are updated to this
shape in task 5 (the documentation change is part of that task).
