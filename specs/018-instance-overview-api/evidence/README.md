# Evidence — spec 018 Instance Overview API

Dev stack, 2026-09-29: container `sentai-task-iris-1` (image `sentai-task-iris-018`, IRIS 2026.2)
mounting this worktree read-only; `iris-target` untouched. No token, password or session id in any
file here: evidence JSON redacts `Authorization`, and temporary accounts used random passwords that
were never written down.

## Suite

| When | Result |
|---|---|
| Baseline (T001), branch after merging `origin/master` (spec 017) | 395 methods, 2,732 assertions, `All PASSED` |
| After this feature (T037) | **440 methods**, 3,070 assertions, `All PASSED` — 45 new methods in `tests/sentai/unittest/overview/` (AreaTable 4, Readings 12, Summary 7, OnDemandReport 4, AreaFlow 5, Secrecy 2, ProcessAction 6) and `rest/OverviewEndpointTest` (5) |

The suite leaves the instance in the monitor's alert state (`$SYSTEM.Monitor.State()` = 2) because
existing dispatch tests provoke `ERROR #7823` (unknown WQM category) at severity 2 on purpose; the
container healthcheck then reports `unhealthy`. Not caused by this feature (no overview call logs
anything); cleared with `do $SYSTEM.Monitor.Clear()` in `%SYS` after the runs below.

## Quickstart scenarios (live, `curl`/Python against `/csp/sentai/api/v1`)

| # | Scenario | Result |
|---|---|---|
| 1 | Seven readings (SC-001) | all 200; slowest `locks` 172 ms; `processes` 53 rows = the platform's 53 read at the same moment; no `ID`, `DeleteID`, `CSPSessionID` or `ServerIP` in any answer |
| 2 | `memory` computed column | `SMHUsedPercent` on every row, `Total` 87.3 %; `computed = ["SMHUsedPercent"]` |
| 3 | Unknown readings (SC-005) | `readings/security`, `readings/nope` → 404 |
| 4 | Summary as `_SYSTEM` (SC-002) | 200 in 0.25 s, 11 entries all `ok`; headlines e.g. processes 53 (busiest `%SYS.WorkQueueMgr`), memory 86.4 % (most used: Security System 100 %), licenses 1 of 8, accounts 7 of 9 enabled, 26 web apps, 5 serious alerts, 1 wallet collection |
| 5 | Summary as a temporary account with only the `SentaiDemo` role (spec 011's `PRIMARY_RESOURCES`; SC-003) | `security`, `web-apps`, `secrets` **refused** (403, `platformStatus` present — the platform sent an empty status, shown as `HTTP 403: no reason given`); `processes`, `locks`, `memory`, `activity`, `devices`, `licenses`, `web-sessions`, `alerts` **ok**. Account and role removed after the run |
| 6 | On-demand `web-app-inventory` vs a one-step run (SC-004) | same 5 findings, same order; the stored step result has no `truncated` / `findingsOmitted`; the run list did not change with the on-demand call |
| 7 | `reports/integrity-check` | 422 `STEP_TYPE_NOT_A_REPORT` (unit test proves no platform call) |
| 8 | `areas/secrets/flow` → `/schedule` daily a minute ahead (SC-007) | 201, flow `Check: Secrets inventory`, 0 validation errors; task 1000 `Daily at 21:25`; the scheduled run (`trigger: scheduled`) completed with the secrets inventory report; unscheduled (200) |
| 9 | `areas/processes/flow` | 409 `AREA_HAS_NO_STEP_TYPE` (unit test) |
| 10 | `readings/processes?target=iris-target` (FR-018) | 400 `OVERVIEW_PRIMARY_ONLY` |
| 11 | Process actions on a disposable `USER` process running `hang 300` (SC-008) | suspend → 200, state `SUSP`; resume → 200, `HANG`; terminate without confirmation → 428, no record; terminate with `{"confirmation": "<pid>"}` → 200, process gone (`process: null`); `process-actions` lists 3 records, newest first |

## T029 spike — process actions (spec 001 envelope)

| File | Call | Finding |
|---|---|---|
| [01-process-suspend.json](01-process-suspend.json) | `POST /api/admin/v2/process/suspend?id=<pid>` | 200; re-read `State: SUSP`, `CanBeSuspended: false` |
| [02-process-resume.json](02-process-resume.json) | `POST …/process/resume?id=<pid>` | 200; re-read `State: HANG` |
| [03-process-terminate.json](03-process-terminate.json) | `POST …/process/terminate?id=<pid>` as `_SYSTEM` | 200; re-read 404, the process is gone |
| [04-process-refused.json](04-process-refused.json) | the same terminate as an operator with `%Admin_Manage:U` and `%DB_IRISSYS:R` only | 403 with an empty status object; the process kept running |

**Verdict: usable.** The body shapes `{"pid": n}`, `{"Pid": n}` and `{"id": n}` all answer 400
`ERROR #40300: Query parameter 'id' is required` — the pid goes in the query string and the body is
empty. The published description types the body as an untyped `string`; this is the deviation
recorded. T030–T033 were built; T034 (document the gap) was not needed.

## Clean-up (T038)

Removed after the live scenarios: flows 456 (`Check: Web application inventory`) and 457
(`Check: Secrets inventory`) with their 2 runs, 2 step runs and 8 log entries; the 3 process-action
records of scenario 11; the temporary accounts `ovw-test` and `spike018` and roles `SentaiDemo` and
`SpikeRole018` (none existed before). Native task 1000 was removed by the unschedule.
