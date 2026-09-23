# Quickstart evidence — real IRIS instance (T070, T073)

- Instance: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.2 (Build 221U), container
  `sentai-task-iris-1`, namespace `IRISAPP`, private web server (Apache) on `localhost:52773`
- Date: 2026-09-23 · Operator credential: `_SYSTEM` (dev instance)
- REST app `/csp/sentai/api/v1` registered by the build (`module.xml` `CSPApplication`, added in this
  round): password + JWT authentication, 60 s access token (same settings as `/api/admin`), never
  Unauthenticated, no `MatchRoles`
- Raw record of the final run (status + body per call, no tokens):
  [`evidence/quickstart-http-20260923.json`](evidence/quickstart-http-20260923.json); SSE timing:
  [`evidence/sse-timing-20260923.txt`](evidence/sse-timing-20260923.txt)
- Every call below went over HTTP with a fresh token from `POST /api/admin/login`
- Automated suite on the same instance: `zpm "test sentai-task -v -only"` — 86/86

## Steps 1–10 (final run, after the fixes listed below)

| Step | Call | Expected | Observed |
|---|---|---|---|
| Build | `GET /flows` without token | 401 | **401** |
| 1 | `POST /flows` canonical 5-step graph | 201, `id`, `revision: 1` | **201**, revision 1 |
| 2 | `GET /flows/{id}` | identical structure | **200**, identical to the create response |
| 3 | `PUT /flows/{id}` + cycle-closing edge | 422 `CYCLE_DETECTED`, nothing persisted | **422** `CYCLE_DETECTED`; flow still revision 1 with 4 edges |
| 4 | `POST /flows/{id}/validate` | `errors: []` | **200** `{"errors":[],"warnings":[]}` |
| 5 | `POST /flows/{id}/dispatch` + typed confirmation for 04 | 202; all 5 StepRuns with `guid`/`timeQueued` | **202**; 5 StepRuns, all with `guid` and `timeQueued` |
| 6 | poll `GET /runs/{guid}` every 3 s | 01–03 `running` in parallel; 04 `queued` until all three complete | **as expected**: 01, 02, 03 `running` at t=0, `completed` at ~30 s (real integrity checks); 04 stayed `queued` until then. 04 then `failed` — `/api/admin/v2/audit/purge returned HTTP 404` (TD-02); 05 `failed` via join propagation; run `failed` at 30.4 s |
| 7 | pause step 01 (integrity-check) | 409, step not paused | **409** `SentaiNotPausable`; step 01 unchanged (`completed`) |
| 8 | `PUT /wqm/categories/SENTAI.NIGHT` violating the invariant | 422 | **422** `SentaiInvariantViolated` |
| 9 | `POST /flows/{id}/schedule` on the destructive canonical flow | 422 `DESTRUCTIVE_NOT_SCHEDULABLE`, no `%SYS.Task` | **422**, one error for step `04`; `SentaiTask: <id>#` tasks: **0**; all `%SYS.Task`: **16 → 16** |
| 10 | `POST /flows/{id}/schedule` on a non-destructive flow | 201, one `taskId` per step, `nextRun` | **201**, 5 `taskIds`, `nextRun` present; 5 tasks removed in teardown (0 left) |

Deviation from the written quickstart: step 5–6 used WQM category `Default` for every step. The
canonical `SENTAI.NIGHT` category does not exist on the instance and could not be created through
the product (finding F-3 below); with it, every step fails at enqueue with the platform's own
message (`ERROR #7823: Invalid work queue manager category supplied 'SENTAI.NIGHT'`).

## Defects found and fixed during this run (each with a failing test first)

| Symptom on the real instance | Cause | Fix | Test |
|---|---|---|---|
| Step 6: all steps `queued` forever, no process, no error | `StartStep` instantiated `%SYS.WorkQueueMgr` (not an accessible class); the background job died silently | `$SYSTEM.WorkMgr.%New(,,category)` + `Sync()`; an unknown category fails the step with the platform message | `StartStepTest` |
| Worker never started the step | `StartStep`/`RunLoop` held exclusive locks the worker needed; `ExecuteStepAsync` swallowed the open failure | concurrency 0 where no lock is needed; `ExecuteStepAsync` returns the error | `StartStepTest` |
| `integrity-check` start → 400 "HTTP POST has no content" | empty POST; platform requires a JSON body (spec 001 evidence 06) | POST `{}` | `StartStepTest` (asserts posted body) |
| Pause posted to `<adminJobId>/pause` | not the validated URL | `POST /api/admin/v2/async-result/pause?id=<id>` (spec 001 evidence 08a) | `PauseControlTest` |
| A `failed` step flipped back to `queued` (terminal state undone) | `TransitionTo` took an exclusive object lock on the Run; the loop process kept that lock for the whole run, so worker transitions timed out and rolled back | `eventVersion` bumped by a row-level SQL update inside the transition; no object lock | `ConcurrentTransitionTest` (reproduced `#5803`) |
| `GET /runs/{guid}/events` → 500 | `%response.WriteFlush` / `IsClientConnected` do not exist | `%response.Flush()`; client disconnect ends the stream via write error; run re-read each pass (`%Reload`) | `SseProtocolTest` |
| SSE events delivered only when the stream ended | `%CSP.REST` sets `AllowOutputFlush = 0`, so every flush was ignored | `AllowOutputFlush = 1` in `StreamEvents` | `SseProtocolTest` |

## Technical Done Criteria

- **TD-01 — authentication: PASS, with an escalation.** No token → 401; malformed → 401; expired
  (19 min old) → 401. A token issued by `/api/admin/login` is accepted natively by the CSP layer of
  `/csp/sentai/api/v1` (JWT auth enabled) and by `OnPreDispatch`'s `/api/admin/info` check; a
  token from `/csp/sentai/api/v1/login` works too. **Escalation E-1:** the background dispatch job
  forwards the operator's 60-second access token to the platform and has no way to refresh it —
  observed: calls made ~67 s after dispatch returned **401**. Any step started, polled, paused or
  cancelled more than 60 s after dispatch cannot reach the platform. Needs a decision (e.g. carry
  the refresh token, or a server-side identity for the job) — not resolved here.
- **TD-02 — per-step-type execution: FAIL for 5 of 7 types (escalation E-2).** `integrity-check`
  proven end to end (start 202 → polled → `Finished` → `completed`). Of the assumed endpoints, GET
  probes (no job started) show `database-dir/defragment` exists (405) and **`database-dir/compact-globals`,
  `journal/switch`, `audit/purge`, `task-history/purge`, `task/custom` return 404**. Observed in step
  6: `purge-audit-records` fails with 404. Also: the start request body is `{}`, so the step's
  `databaseDirectory` is not forwarded — which databases the platform checks is not controlled by
  the step.
- **TD-03 — SSE: PASS after fix.** Transitions injected every 8 s were received at the second they
  were emitted (arrival = server `at`, ≤ 1 s), `eventVersion` non-decreasing, `run-terminal` last and
  the stream closed. Runs longer than `sseMaxDurationSeconds` (default 600 s) close the stream; the
  client falls back to reconnect/polling. 3 s polling (step 6) reads the same persisted state.
- **TD-04 — scheduled ordering for non-destructive flows: NOT DEMONSTRABLE (escalation E-3).** A
  scheduled non-destructive flow's root task was fired by the Task Manager (`RunNow`, task 1110 ran
  at 04:02:00) and by calling `ScheduledFlowTask.OnTask()` directly: both created a run
  (`dispatchedBy = $SCHEDULER`) and the wave order held (04/05 failed only via join propagation),
  but **every platform call returned 401** — a scheduled run has no operator token at all
  (`StartBackgroundLoop(run.guid, "")`). Scheduled execution cannot work until E-1 is decided.
- **TD-05 — assumptions explicit:** recorded here and in `HANDOFF.md` (E-1…E-3, F-1…F-5).
- **TD-06 — destructive scheduling refused: PASS over HTTP** (step 9: 422
  `DESTRUCTIVE_NOT_SCHEDULABLE` for step 04, zero `%SYS.Task` created, instance count unchanged).

## Follow-up findings (not fixed in this round)

- **F-1** `CategoryService.Write` posts to `POST /api/admin/v2/wqm-categories/<name>`; the validated
  contract is `PUT /api/admin/v2/wqm-category?name=<name>` (spec 001 evidence 10a). A valid category
  write cannot succeed against the real platform; the unit test double accepts the wrong path.
- **F-2** `CancelStep`/`CancelRun` only change local state; the running platform job is never
  cancelled (validated endpoint: `POST /api/admin/v2/async-result/cancel?id=`, evidence 08c).
- **F-3** Creating a WQM category is not possible through the product (F-1), and `FlowValidator`
  does not check that a step's category exists — the failure only surfaces at enqueue time.
- **F-4** Real categories report `MaxTotalWorkers = 0` (apparently "unbounded") and `Dynamic (N)`
  values; the nesting invariant as written would flag every built-in category as violating.
- **F-5** Test-suite hygiene: `DispatchEndpointTest` starts real background jobs, and runs created by
  the suite (and by loops that died before the fixes) stay `running` in `IRISAPP` (527 on
  2026-09-23; no dispatch loop process alive).
