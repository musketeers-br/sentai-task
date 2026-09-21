# Compatibility Statement

**Feature**: 001-validate-async-job-contract
**Run captured**: 2026-09-20T23:45:18Z

## Environment

- **Platform version**: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.2 (Build 221U) Fri Jun 26 2026 09:59:12 EDT
- **Image digest**: `sha256:8a206381c3456481e94c8b402cc975993a6e48685d0921ae1843668193856e92`
- **Base URL**: http://localhost:51764
- **Run timestamp**: 2026-09-20T23:45:18Z

## Q1 — Reachability and authentication

The management API responded on the freely available Community edition.
- Login (`POST /api/admin/login`): HTTP 200. See [evidence/01-login.json](evidence/01-login.json).
- **Deviation**: the published contract implies a JSON `{username,password}` body; the platform instead requires HTTP Basic Auth (`-u user:pass`) with the request body unused. The successful envelope is flat — `{access_token, refresh_token, sub, iat, exp}` — not the `{status,console,result}` wrapper every other admin endpoint uses.
- Session renewal (`POST /api/admin/refresh`): HTTP 200. Requires the current `access_token` as a Bearer header plus `{"refresh_token": ...}` in the body; returns a fresh access/refresh pair in the same flat shape. See [evidence/02-refresh.json](evidence/02-refresh.json).
- Platform/version info (`GET /api/admin/info`): HTTP 200, wrapped in `{status,console,result}`; `result.serverVersion` is the platform version string used throughout this statement. See [evidence/00-info.json](evidence/00-info.json).

## Q2 — Response shapes

- List (`GET /api/admin/v2/tasks`): wrapped `{status,console,result:[...]}`; each element carries `Id` (small integer, e.g. 1, 4), `Name`, `Type`, `Namespace`, `Description`, `Suspended`, `LastFinished`, `NextScheduled`. See [evidence/03-tasks-list.json](evidence/03-tasks-list.json).
- Single (`GET /api/admin/v2/task?id=`): wrapped; a much larger object including scheduling fields (`TimePeriod*`, `DailyFrequency*`, `StartDate`), `TaskClass`, `RunAsUser`, and — critically — `RunAfterGUID` (see Q6). See [evidence/04-task-single.json](evidence/04-task-single.json).
- Info (`GET /api/admin/v2/task/info?id=`): wrapped; runtime-status-only fields — `Type`, `Status`, `Error`, `LastSchedule`, `LastStarted`, `LastFinished`, `NextScheduled`, `Suspended`. Does not include `RunAfterGUID`. See [evidence/05-task-info.json](evidence/05-task-info.json).
- The task's own list identifier (`Id`) is present and is what `?id=` expects on both the single-task and info reads; confirmed by successful HTTP 200 responses on both.

## Q3 — Long-running operations

`POST /api/admin/v2/database-dir/integrity-check` returned HTTP 202 (accepted-for-processing), carrying no job identifier in the response body but a `Location` header pointing at the async-result resource: `/api/admin/v1/async-result?id=882998815990347262254421`. See [evidence/06-integrity-check-start.json](evidence/06-integrity-check-start.json).
- **Deviation**: the Location header uses `/api/admin/v1/async-result`, not `v2`, despite the triggering call being a `v2` endpoint. Both `v1` and `v2` forms of `GET .../async-result?id=...` were verified to respond identically for the same job id.

## Q4 — Job observation and control

- **State**: observed transitioning Running → Finished across polls (first: `Running`, settled: `Finished`). See [evidence/07a-async-result-first.json](evidence/07a-async-result-first.json), [evidence/07b-async-result-midflight.json](evidence/07b-async-result-midflight.json), [evidence/07c-async-result-settled.json](evidence/07c-async-result-settled.json).
- **Timings**: TimeQueued=`2026-09-20 23:44:56`, TimeStarted=`2026-09-20 23:44:56`, TimeFinished=`2026-09-20 23:45:17` — all populated on natural completion.
- **Failure reason**: the `FailureReason` field is present on every poll (observed as `""` on the success path in this run). This run's job completed successfully, so a populated failure string was not observed; treated as an **open risk** below, not a spike-closing negative, per the plan's guidance.
- **Pause**: HTTP 200; post-transition read reported State=Paused. See [evidence/08a-async-result-pause.json](evidence/08a-async-result-pause.json).
- **Resume**: HTTP 200; post-transition read reported State=Running. See [evidence/08b-async-result-resume.json](evidence/08b-async-result-resume.json).
- **Cancel**: HTTP 200; post-transition read reported State=Canceled. See [evidence/08c-async-result-cancel.json](evidence/08c-async-result-cancel.json).
- **Note**: `TimeFinished` was observed to remain empty after a Cancel transition (cancellation is not treated as a form of completion by the timings field).

## Q5 — Resource ceilings

- Read (`GET /api/admin/v2/wqm-categories`): HTTP 200; returns an array of `{Name, MaxActiveWorkers, DefaultWorkers, MaxWorkers, MaxTotalWorkers, AlwaysQueue}`. See [evidence/09-wqm-categories.json](evidence/09-wqm-categories.json).
- Write (`PUT /api/admin/v2/wqm-category?name=...`): HTTP 200. **Deviation**: `name` is a query parameter, not a body field — a body-only `Name` was rejected with `ERROR #40300`. See [evidence/10a-wqm-category-write.json](evidence/10a-wqm-category-write.json).
- Read-back (`GET /api/admin/v2/wqm-categories` again): HTTP 200. Write took effect and was confirmed on read-back (see notes), then restored to its original value as housekeeping (recorded in the same file's notes, not as a separate evidence file). See [evidence/10b-wqm-categories-verify.json](evidence/10b-wqm-categories-verify.json).

## Q6 — Task chaining identifier

**Found.** The predecessor identifier is obtainable via the `RunAfterGUID` field, present in the single-task read (`GET /api/admin/v2/task?id=`) but absent from both the list read and the info read. It is empty for tasks with no configured predecessor (as expected — none of the system tasks on a fresh Community instance are chained), but its presence in the schema directly answers Q6: yes, a dependent task's predecessor identifier is obtainable. See [evidence/11-chaining-probe.json](evidence/11-chaining-probe.json) and [evidence/04-task-single.json](evidence/04-task-single.json).

## Deviations from the published contract

- Login is HTTP Basic Auth, not a JSON `{username,password}` body; the login/refresh response envelope is flat, unlike every other admin endpoint's `{status,console,result}` wrapper.
- The accepted-for-processing `Location` header for an async job points at a `v1` path even when triggered from a `v2` endpoint (both respond identically for the same job id).
- `PUT /api/admin/v2/wqm-category` requires `name` as a query parameter; a body-only `Name` field is rejected.
- `RunAfterGUID` (the task-chaining identifier) is present only on the single-task read, not on the list or the info read.

## Open risks

- **Q4 (failure reason)**: this run's integrity-check job completed successfully; a populated `FailureReason` value on a genuinely failed job was not observed. **Blocks**: any downstream feature that surfaces failure diagnostics to the operator should budget a follow-up spike run against a deliberately-failing operation before that feature ships.

## Prior-run archive

A prior run's evidence, compatibility statement, and decision were archived to `evidence/.archive/20260920-234455Z/` before this run wrote anything new.
