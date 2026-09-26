# API Contract Delta — 005 Declared Custom Steps

Base: `/csp/sentai/api/v1` after spec 004. **No new endpoint. No request shape change.** All
changes are additive fields and new validation codes.

## `GET /catalog/step-types` — entries gain `label`, `executor`, `parameters`

```json
[
  { "type": "integrity-check", "label": "Integrity check", "class": "%SYS.Task.IntegrityCheck",
    "category": "verification", "executor": "platform-api",
    "destructive": false, "pausable": false, "available": true },

  { "type": "storage-headroom-check", "label": "Storage headroom check",
    "class": "sentai.steps.StorageHeadroomCheck", "category": "storage", "executor": "in-process",
    "destructive": false, "pausable": false, "available": true,
    "parameters": [
      { "name": "minFreePercent", "property": "MinFreePercent", "type": "number",
        "required": false, "default": 10, "min": 0, "max": 100,
        "description": "Fail when any database or journal location has less free space than this percentage" }
    ] },

  { "type": "db-size-report", "label": "Database size report",
    "class": "sentai.steps.DatabaseSizeReport", "category": "verification", "executor": "in-process",
    "destructive": false, "pausable": false, "available": true, "parameters": [] },

  { "type": "switch-journal", "label": "Switch journal", "class": "%SYS.Task.SwitchJournal",
    "category": "journal", "executor": "in-process",
    "destructive": false, "pausable": false, "available": true, "parameters": [] },

  { "type": "purge-task-history", "label": "Purge task history",
    "class": "%SYS.Task.PurgeTaskHistory", "category": "purge", "executor": "in-process",
    "destructive": true, "pausable": false, "available": true,
    "parameters": [
      { "name": "keepDays", "property": "KeepDays", "type": "integer",
        "required": false, "default": 30, "min": 0,
        "description": "Days of task history to keep" }
    ] },

  { "type": "custom", "label": "Custom (legacy)", "class": "", "category": "custom",
    "executor": "platform-api", "destructive": false, "pausable": false, "available": false }
]
```

`available: true` for the in-process types only once their quickstart evidence is recorded.
`purge-task-history.pausable` becomes `false` (in-process work has no pause), superseding the
spec 003 "purge family pausable" value for this type only.

## `POST /flows/{id}/validate` — new codes

```json
{"errors":[
  {"stepId":"02","code":"PARAM_REQUIRED","parameter":"keepDays","message":"Step '02' (purge-task-history): parameter 'keepDays' is required"},
  {"stepId":"02","code":"PARAM_TYPE_MISMATCH","parameter":"keepDays","message":"Step '02' (purge-task-history): parameter 'keepDays' must be an integer"},
  {"stepId":"01","code":"PARAM_OUT_OF_RANGE","parameter":"minFreePercent","message":"Step '01' (storage-headroom-check): parameter 'minFreePercent' must be between 0 and 100"},
  {"stepId":"01","code":"PARAM_UNKNOWN","parameter":"path","message":"Step '01' (storage-headroom-check): unknown parameter 'path'"},
  {"stepId":"03","code":"STEP_TYPE_NOT_SUPPORTED_ON_TARGET","message":"Step type 'db-size-report' is not supported on the target platform: its declared class is not installed"}
 ],"warnings":[]}
```

`parameter` (additive, spec 007 BD-1) names the parameter a `PARAM_*` finding concerns — for
`PARAM_UNKNOWN`, the unknown key. Clients match on it and never parse `message`.

Dispatch and schedule return 422 with the same report (unchanged mechanism). `/schedule` also
reports, per in-process step:

```json
{"stepId":"01","code":"IN_PROCESS_NOT_SCHEDULABLE","message":"Step '01' (storage-headroom-check) runs inside the platform as the dispatching operator and cannot run in a scheduled run"}
```

## Identity refusals (request level)

| Call | Status | Body `code` | When |
|---|---|---|---|
| `POST /flows/{id}/dispatch` with `runCredential` | 403 | `RUN_CREDENTIAL_USER_MISMATCH` | the redeemed credential belongs to another user; no run created |
| `POST /runs/{guid}/steps/{stepGuid}/rerun` | 403 | `RERUN_NOT_BY_DISPATCHER` | requester ≠ the run's dispatcher |

Both use the existing problem shape (`status`, `title`, `detail`), with the code at the start of
`detail`.

## `GET /runs/{guid}` — `steps[]` gain `result` and `executedAs`

```json
{ "stepId": "02", "state": "completed", "failureReason": "", "executedAs": "_SYSTEM",
  "result": { "databases": [ { "name": "IRISAPP_DATA", "directory": "/data/IRISAPP_DATA/",
                               "sizeMB": 11, "freeMB": 3 } ] } }
```

`result` is `{}` for steps that produce none; when over 8000 characters it carries
`"truncated": true` (see data-model). `executedAs` is `""` for management-API steps. Failed steps
keep `failureReason` verbatim.

## Unchanged

`/dispatch` typed confirmation (now also for `purge-task-history`); `DESTRUCTIVE_NOT_SCHEDULABLE`;
scheduling still non-operational (spec 004 D-2); cancel local only (F-2); event stream (worker
transitions bump `eventVersion` like any other).
