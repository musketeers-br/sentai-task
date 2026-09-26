# Tasks: Task Catalog API (backend)

**Input**: Design documents from `/specs/006-task-catalog-api/`. [plan.md](plan.md) is the source
of truth where it conflicts with [spec.md](spec.md), because the platform facts were proven in
[research.md](research.md) (R-1…R-5). Also used: [data-model.md](data-model.md),
[contracts/api-delta.md](contracts/api-delta.md) and [quickstart.md](quickstart.md).

**Tests**: REQUIRED (Constitution: TDD). Every code task writes or adjusts its failing test
**first**, then the code, then runs the suite. No test method is deleted.

**Run the backend suite** from the repo root. Every code task ends with this command:

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'X'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
halt
X
```

**Test baseline**: the backend count at the start of 006 (122, or the post-005 count if 005 has
landed) **+ ≈ 47** (the plan estimated ≈ 40; the breakdown is at the end). Two tests are adjusted, both in `CatalogTasksTest` (one in T001, one in T005),
and none are removed. Frontend unit **48/48** and e2e **13/13** stay unchanged: `/catalog/tasks`
has no frontend consumer. Check them with `cd frontend && npm run generate:tokens && npm test` and
`npx playwright test`.

**Hard rules for every task** (Constitution II/III, plan):

- **Operator token.** Every platform call uses the **requesting operator's bearer token**
  (`Dispatcher.CurrentToken()`, passed down as `bearerToken`). A token is never logged, never
  stored and never written to an evidence file. Evidence headers are `<REDACTED>`, and the
  repository is public.
- **Fixed platform paths.** Every platform path is a fixed string. The task id is validated as a
  positive integer (`?1.N` and `> 0`) before it is used in a URL.
- **Filters are data.** No SQL is built from input. The only SQL is `sentai.model.Flow.%ExistsId`
  and the parameterized `SELECT type FROM sentai_model.Step WHERE flow = ? AND id = ?`. There is
  no `Xecute`, no `$CLASSMETHOD` on input and no class or method name taken from a request.
- **Refusals are verbatim.** The platform's HTTP status and its `status` object (`platformStatus`)
  are passed on as values. Nothing is paraphrased, and no reason is added to an empty 403.
- **Out of scope.** No new endpoint and no flow-schema change. No task is created, edited or
  deleted, and there is no run-now or schedule change (spec 004 D-2). Test setup creates platform
  tasks only on the real instance, during quickstart, and deletes them afterwards.
- **Sequential files.** `src/sentai/catalog/TaskService.cls` and `src/sentai/rest/Dispatcher.cls`
  are edited in sequence: T001 → T005 → T006. Never edit either in two tasks at once.
- **Platform double.** The double is `sentai.unittest.AdminApiDouble`. GET responses are keyed by
  the **full** URL including the query (`/api/admin/v2/task?id=4`, `/api/admin/v2/task/info?id=4`,
  `/api/admin/v2/task/history?taskId=4`). POST responses are keyed by the base path, and the full
  URL and body are recorded in `^sentaiTestDouble("posted", base)`. GET records the bearer used in
  `^sentaiTestDouble("gets", url)`. Build any scripted body that holds a serialized `%Status` from
  a `%DynamicObject` (`%Set` + `%ToJSON`), so that control characters are escaped.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency on an incomplete task).
- **[Story]**: US1 see what each task really is · US2 recognise what SentaiTask scheduled ·
  US4 filters · US3 suspend/resume · US5 recent runs.
- **Plan row → tasks**: row 1 → T001 · row 2 → T002, T003 · row 3 → T004 · row 4 → T005 ·
  row 5 → T006–T009.
- **Why rows stay whole** (analysis C1/C2): **Constitution V takes precedence over the "split a
  row that touches more than 2 source files" rule.** A task must deliver behaviour an operator
  can observe over REST, with its test. So plan row 1 stays one task (T001, 4 source files), and
  the catalog helper is merged with its first use (T002). Row 2 is split only where each part is
  observable on its own: destructiveness in T002, origin in T003. Row 5 is split into code (T006),
  docs (T007), script (T008) and evidence (T009).

---

## Phase 1: Setup (docs only)

- [ ] T000 Apply the plan's "Spec deviations" table, plus the analysis items I1, I2 and I7, to
  `specs/006-task-catalog-api/spec.md`. This is docs only, about 10 minutes, with no code.
  1. Add a `## Clarifications` section after "Objective", with `### Session 2026-09-26` bullets
     pointing to [research.md](research.md) R-1…R-5: the read source (management API), the lossy
     list, the proven suspend/resume contract, the proven history read, and the empty and
     timestamp values.
  2. **US-3 Independent Test**: replace "and it no longer shows a next run" with "(its next run is
     returned as the platform reports it; a suspended task keeps it, R-3)".
  3. **SC-004**: judge on `suspended` from the platform's info read after each call, return
     `nextRun` verbatim, and remove the "if the contract is not proven…" clause.
  4. **FR-006**, US-3 scenario 4 and Scope item 2: delete the "not supported on the target
     platform" fallback, noting that the contract was proven (R-3). Add "a platform 200 without the
     requested state → `502 SUSPEND_NOT_APPLIED`".
  5. **US-1 scenario 3**: append "(the audit purge's platform class is `%SYS.Task.PurgeAudit`; the
     step-type catalog is corrected by plan D-4)".
  6. **FR-010**: append "`isDestructive` and `lastRun` are kept as deprecated aliases carrying the
     corrected values (`destructive`, `lastFinished`)".
  7. **Edge Cases**: add "**Invalid filter value** (`filter` outside `all|scheduled|suspended`, or
     `destructiveOnly` outside `0|1|true|false`): 400 `INVALID_FILTER`, no platform call".
  8. **FR-003 and SC-001 (I1)**: define `status` as "the platform's `Status` passed through when
     it is `"1"` (or any value that is not a serialized error), or the platform's own text for a
     serialized `%Status` (`$SYSTEM.Status.GetErrorText`), which equals the history `Status` and
     `DisplayStatus` (R-5)". Also state that `lastError` is the platform's `Error` field verbatim,
     including `"Success"`.
  9. **US-5 (I2)**: replace "(when, how long, outcome)" with "(start, completion and outcome as
     the platform reports them, at the platform's minute precision; no duration is computed)".
  10. **SC-006 (I7)**: change "Delivered within ~5 tasks" to "Delivered within ~5 plan-level
      increments".

  Do not change any other text. Commit the change as docs only.

---

## Phase 2: Foundational

None. The corrected read of US1 (T001) is the base that every later story builds on.

---

## Phase 3: User Story 1 — See what each task really is (P1) 🎯 MVP

**Goal**: list and item read return class, run-as user, time period, next run, last
started/finished, status, last error and suspended, all from the platform's reads. Failed per-task
reads are visible, `state` and `className` are gone, and destructiveness comes from the catalog.

**Independent test**: with the double scripting list, single and info reads, every field equals its
source key (see the data-model table). On the real instance this is quickstart (a).

- [ ] T001 [US1] Implement the corrected read end to end, across four source files:
  `src/sentai/catalog/TaskShape.cls` (new, pure mapping), `src/sentai/catalog/TaskFilter.cls`
  (new skeleton), `src/sentai/catalog/TaskService.cls` (rewrite of the reads) and
  `src/sentai/rest/Dispatcher.cls` (outcome mapping). This is one task by Constitution V; see
  Format.

  **Test first** in `tests/sentai/unittest/catalog/TaskReadTest.cls` (extends
  `sentai.unittest.SentaiTestCase`). The pure mapping tests live here too (analysis U1), so there
  is no separate `TaskShapeTest`. Eleven tests.

  *Mapping (pure, no double):*
  1. `TaskShape.Build(listEntry, singleRead, infoRead)` maps every field per the data-model table:
     `taskId`, `name` and `namespace` from the list entry; `class`, `runAsUser` and `timePeriod`
     from single `TaskClass`/`RunAsUser`/`TimePeriod`; `nextRun`, `lastStarted`, `lastFinished`,
     `lastError` and `suspended` from info; aliases `lastRun = lastFinished` and
     `isDestructive = destructive`. No `state` or `className` key.
  2. `status`: `"1"` stays `"1"`. A serialized `%Status` built with
     `$$$ERROR($$$GeneralError,"x")` becomes `$SYSTEM.Status.GetErrorText` of it
     (`ERROR #5001: x`). Any other string is passed through unchanged.
  3. `lastError` `"Success"` is passed through verbatim, and `""` is passed through as `""`.
  4. A single read with `httpStatus 404` → `class`, `runAsUser` and `timePeriod` are absent, and
     `unavailable = [{read:"single", fields:["class","runAsUser","timePeriod"], httpStatus:404,
     platformStatus:<status object verbatim>}]`.
  5. An info read with `httpStatus 403` and `{"errors":[],"summary":""}` → the six info fields are
     absent, and `unavailable[0].platformStatus` equals `{"errors":[],"summary":""}` exactly.

  *Service and REST, using the double:*
  6. The list says `"Suspended":false` for task 4 while info says `true` → the item has
     `suspended:true`. This is R-1: the list is never a source for `suspended` or `nextRun`.
  7. List 403 with `{"status":{"errors":[],"summary":""},…}` → the outcome is `httpStatus 403`, the
     Problem has `detail ""` and `platformStatus` verbatim, and there are no items.
  8. `Read(4)` returns the same corrected values as the list item for task 4, excluding
     `recentRuns`.
  9. `Read(99999)` with single 404 `ERROR #5809…` → 404, where `detail` is the platform's
     `errors[0].error` and `platformStatus` is verbatim.
  10. `ReadCatalogTask("abc")` and `"0"` → 404 with **no** platform GET recorded.
  11. Every GET recorded in `^sentaiTestDouble("gets", …)` carries the requesting token
      (`"fake-token"`). A platform status of `0` (unreachable) → 502 `PLATFORM_UNREACHABLE`.

  **Adjust** `tests/sentai/unittest/rest/CatalogTasksTest.cls`
  `TestNonProductTasksAppearAndAreFilterable` so that it also scripts the single and info reads for
  `Id 1`. Keep its `total`/`matched` assertions. This is adjusted test 1 of 2.

  Implementation:
  - **TaskShape.** Each read is passed in as a value `{httpStatus, result, status}`
    (`%DynamicObject`). Destructiveness for now is always
    `destructive:false, destructiveUnknown:true` (the honest interim; T002 refines it).
  - **TaskFilter.** Provides `Validate(q, namespace, filter, destructiveOnly, Output problem) As
    %Boolean`, which for now accepts every value, and `Matches(task, q, namespace, filter,
    destructiveOnly) As %Boolean`, a straight port of today's in-memory rules (`q` on name;
    `namespace` equal; `scheduled`/`suspended`; destructive only). It reads the **corrected**
    `suspended` and `destructive`. T004 replaces its semantics.
  - **TaskService.List.** `List(bearerToken, q, namespace, filter, destructiveOnly) As
    %DynamicObject` returns an outcome `{httpStatus, body}`. It calls `TaskFilter.Validate`
    (400 outcome on refusal), then the list read → for each `Id`, single + info reads
    (sequential, R-2) → `TaskShape.Build` → `TaskFilter.Matches`. The body is
    `{total, matched, items}`, unchanged.
  - **TaskService.Read.** `Read(taskId, bearerToken)` makes a single read and an info read.
  - Use `AdminApiClient.Get` per read and keep the parsed body's `status` object.
  - **Dispatcher.** Add `WriteOutcome(outcome)`, which writes `body` with `httpStatus`, or a
    Problem `{status,title,detail}` plus the additive `platformStatus`/`platformInfo`.
    `ListCatalogTasks` and `ReadCatalogTask` call the service and `WriteOutcome`, and
    `ReadCatalogTask` no longer re-lists.

  Run the suite. **Checkpoint**: US1 fields are true over REST. Destructiveness is still
  "unknown".

- [ ] T002 [US1] Derive destructiveness from the step-type catalog: `DestructiveByClass` and the
  D-4 fix in `src/sentai/registry/StepType.cls`, plus rules 1, 2 and 4 in
  `src/sentai/catalog/TaskShape.cls`. Depends on T001. This was plan row 2's catalog part, merged
  with its first use (analysis C2).

  **Rebase on 005's catalog if 005 has landed. Do not reorder or rewrite any 005 entry. Only fix
  the `purge-audit-records` `class` from `%SYS.Task.PurgeAuditDatabase` to
  `%SYS.Task.PurgeAudit` (`available` stays `false`), and add the helper.**

  **Test first.** Six tests:

  *In `tests/sentai/unittest/registry/StepTypeTest.cls`:*
  1. `DestructiveByClass("%SYS.Task.PurgeTaskHistory",.k)` = 1 with `k=1`;
     `DestructiveByClass("%SYS.Task.IntegrityCheck",.k)` = 0 with `k=1`;
     `DestructiveByClass("%SYS.Task.SecurityScan",.k)` = 0 with `k=0`; `""` → `k=0`. Matching is
     exact and case-sensitive, and only on catalog entries with a non-empty `class`.
  2. `GetTargetClass("purge-audit-records") = "%SYS.Task.PurgeAudit"`, and
     `IsAvailable("purge-audit-records") = 0`.

  *In `tests/sentai/unittest/validation/StepAvailabilityRuleTest.cls` (analysis R1), a new
  method:*
  3. `TestPurgeAuditStillRefusedAfterClassFix`: a flow with one `purge-audit-records` step is
     refused on validate with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`, and the message names the type
     as not supported. The refusal comes from `available:false`, even though the corrected class
     is now compiled on the instance. The existing `TestEveryUnavailableTypeIsRefusedOnAllFourPaths`
     must keep passing unchanged.

  *In `tests/sentai/unittest/catalog/TaskOriginDestructiveTest.cls`:*
  4. `class` `%SYS.Task.PurgeTaskHistory` → `destructive:true, destructiveUnknown:false`, and the
     alias `isDestructive:true`.
  5. `class` `%SYS.Task.PurgeAudit` → `destructive:true`. This is US-1 scenario 3, after D-4.
  6. An unknown class (`%SYS.Task.SecurityScan`) → `false/true`, and an unavailable class (failed
     single read) → `false/true`.

  The helper reads through `GetCatalog()` only. Rules follow data-model §Destructiveness. Rule 3
  (`ScheduledFlowTask`) comes in T003, and until then such a task falls under rule 4.

  Run the suite. **Checkpoint**: US1 is complete and observable in `GET /catalog/tasks`.

---

## Phase 4: User Story 2 — Recognise what SentaiTask scheduled (P1)

**Goal**: tasks named by the product's generator carry `origin {flowId, stepId, flowExists}`, and
their destructiveness comes from the step they run.

**Independent test**: scripted names `SentaiTask: 1#01..03` get an origin, near-misses do not, and
a deleted flow gives `flowExists:false`. On the real instance this is quickstart (b).

- [ ] T003 [US2] Create `src/sentai/catalog/TaskOrigin.cls` and attach origin plus destructiveness
  rule 3 in `src/sentai/catalog/TaskShape.cls` (depends on T002).

  **Test first**: add eight tests to `tests/sentai/unittest/catalog/TaskOriginDestructiveTest.cls`.
  1. `TaskOrigin.Parse` accepts `SentaiTask: 1#01`, `SentaiTask: 12#a1` and `SentaiTask: 3#7`.
     Captures are strings: `"1"`/`"01"`, `"12"`/`"a1"`, `"3"`/`"7"`.
  2. Near-miss table → no origin: `SentaiTask: 1#01 copy`, `SentaiTask:1#01`,
     `sentaitask: 1#01`, `SentaiTask: 01#01`, `SentaiTask: 1#`, `SentaiTask: 1#123456789`,
     `SentaiTaskX: 1#01`, `SentaiTask: 1#0 1`.
  3. A flow created with `..CreateSupportedFlow()` and its task name → `flowExists:true`.
  4. The same flow deleted (`sentai.model.Flow.%DeleteId`) → `origin` still present, with
     `flowExists:false`.
  5. `class` `sentai.dispatch.ScheduledFlowTask`, with the flow and step present (step type
     `integrity-check`) → `destructive:false, destructiveUnknown:false`.
  6. The same, but the step is missing (stepId `99`) or the flow is deleted →
     `destructiveUnknown:true`.
  7. A non-product name with class `ScheduledFlowTask` → no origin, and `destructiveUnknown:true`.
  8. **List level (moved here from the old T006, analysis I4)**: through `TaskService.List` with
     the double scripting two tasks (one suspended, one not), `filter=suspended` gives `matched=1`
     and `total=2`. (The `filter=paused` → 400 check is T004 test 10.)

  Implementation:
  - The grammar is `^SentaiTask: ([1-9][0-9]*)#([0-9A-Za-z_-]{1,8})$`, applied via `$MATCH` on the
    platform's name, with the captures taken by `$LOCATE`/`$PIECE`.
  - `FlowExists(flowId)` is `##class(sentai.model.Flow).%ExistsId(flowId)`.
  - `StepTypeOf(flowId, stepId, Output found)` is `%SQL.Statement` with
    `SELECT type FROM sentai_model.Step WHERE flow = ? AND id = ?`, parameters only.
  - `TaskShape.Build` attaches `origin` and applies rule 3 (`StepType.IsDestructive(type)`).
  - Nothing is cached across calls.

  Run the suite. **Checkpoint**: US2 is complete, and `GET /catalog/tasks` is true for US1 and US2.

---

## Phase 5: User Story 4 — Filter the corrected catalog (P2)

This phase comes before US3 to follow the plan order. Both are P2.

**Goal**: `q`, `namespace`, `filter` and `destructiveOnly` operate on the corrected values,
invalid values → 400, and `total`/`matched` give "N of M".

**Independent test**: each filter alone and combined returns exactly the matching items, with
correct counts.

- [ ] T004 [US4] Give `src/sentai/catalog/TaskFilter.cls` its data-model semantics. **Depends on
  T003** (analysis I4: not parallel, because the combined case needs `destructiveUnknown` and
  `origin` in place). Only `TaskFilter.cls` changes; the 400 path is already wired by T001.

  **Test first** in `tests/sentai/unittest/catalog/TaskFilterTest.cls` (pure, hand-built task
  objects), plus one REST check. Ten tests:
  1. `q` matches on name.
  2. `q` matches on class, case-insensitively (`integritycheck` finds `%SYS.Task.IntegrityCheck`).
  3. `q` with `class` unavailable → only the name is matched.
  4. `namespace` is compared case-insensitively (`%sys` = `%SYS`).
  5. `filter=scheduled` keeps `suspended:false` only.
  6. `filter=suspended` keeps `suspended:true`, and a task whose `suspended` is unavailable is
     excluded from both.
  7. `destructiveOnly=1` excludes `destructiveUnknown`.
  8. A combined `q` + `namespace` + `suspended` + `destructiveOnly` case.
  9. `Validate` refuses `filter=paused` and `destructiveOnly=maybe` with problem
     `INVALID_FILTER: …`, and accepts `all|scheduled|suspended` and `0|1|true|false`.
  10. REST: `ListCatalogTasks` with `filter=paused` → 400 `INVALID_FILTER`, with **no** platform
      GET recorded.

  Run the suite. **Checkpoint**: US4 complete.

---

## Phase 6: User Story 3 — Suspend and resume a task (P2)

**Goal**: suspend and resume use the proven platform contract, the result is confirmed by a
re-read, and refusals are verbatim.

**Independent test**: the double records the exact platform call, and the re-read decides between
200 and 502. On the real instance this is quickstart (c) and (d).

- [ ] T005 [US3] Add `SetSuspended(taskId, suspended, bearerToken) As %DynamicObject` (an outcome)
  in `src/sentai/catalog/TaskService.cls`, and rewrite `SuspendCatalogTask` in
  `src/sentai/rest/Dispatcher.cls` (depends on T001; sequential after T001 for these two files).

  **Test first** in `tests/sentai/unittest/catalog/TaskSuspendTest.cls`. Seven tests:
  1. `{suspended:true}` posts `/api/admin/v2/task/suspend?id=1003`, and
     `^sentaiTestDouble("posted","/api/admin/v2/task/suspend")` = `$LB(".../task/suspend?id=1003","{}")`.
     The body is **`{}`, never empty**: an empty body gets 415 on the real platform (R-3).
  2. `{suspended:false}` posts `/api/admin/v2/task/resume?id=1003` with `{}`.
  3. The re-read info shows `Suspended:true` → 200, and the body is the re-read catalog task with
     `suspended:true`.
  4. The re-read shows `Suspended:false` after a suspend → 502, where `detail` starts with
     `SUSPEND_NOT_APPLIED` and `platformInfo` is the info result verbatim.
  5. Platform 403 `{"errors":[],"summary":""}` → 403, `platformStatus` verbatim, and **no** re-read
     GET recorded.
  6. Platform 404 `ERROR #5809…` → 404, with `detail` verbatim.
  7. `{"suspended":"yes"}` → 400 with no platform call. A missing body defaults to `true`, as today.

  **Adjust** `tests/sentai/unittest/rest/CatalogTasksTest.cls`
  `TestSuspendTogglesStateReflectedOnNextRead`: it scripted the unvalidated
  `/api/admin/v2/tasks/1/suspend`. Script `/api/admin/v2/task/suspend` and the re-read info with
  `Suspended:true` instead, and assert the outcome is 200. This is adjusted test 2 of 2. It moved
  here from plan row 1 because the path changes in this task (see the plan note).

  Remove the old `Suspend(taskId, suspended, bearerToken) As %Status` only if nothing else calls
  it. Check with `grep -rn "TaskService).Suspend" src tests`.

  Run the suite. **Checkpoint**: US3 complete.

---

## Phase 7: User Story 5 — Recent runs of a task (P3) ✂ first to cut

**Goal**: the item read returns up to 5 recent **executions**, exactly as the platform's history
reports them.

**Independent test**: scripted history with mixed execution and `TASKMGR` rows → only the
execution rows, at most 5. On the real instance this is quickstart (f).

- [ ] T006 [US5] Add the history read to `Read` in `src/sentai/catalog/TaskService.cls`, and
  `RecentRuns(historyRead, class)` in `src/sentai/catalog/TaskShape.cls` (depends on T005 for
  `TaskService.cls` ordering, and on T003).

  **Test first** in `tests/sentai/unittest/catalog/TaskHistoryTest.cls`. Five tests:
  1. `GET /api/admin/v2/task/history?taskId=1` is scripted with 7 rows, mixing
     `Routine:"TASKMGR"` rows with `Routine:"%SYS.Task.SwitchJournal"` rows → `recentRuns` holds
     only the execution rows, newest first. Each keeps `LastStart`, `Completed`, `Status`,
     `Result`, `Username` and `LogDatetime` verbatim, and no duration key is added.
  2. Eight execution rows → exactly 5 are returned.
  3. Only `TASKMGR` rows → `recentRuns: []`.
  4. The history read returns 403, or the single read failed so `class` is unavailable →
     `recentRuns` is absent, and `unavailable` has a `read:"history"` entry with
     `fields:["recentRuns"]` and the verbatim `platformStatus`.
  5. `List` items never carry `recentRuns`, and no history GET is recorded during `List`.

  **If cut**: skip this task, leave `recentRuns` absent, and write the reason in the README (T007).

  Run the suite. **Checkpoint**: US5 complete.

---

## Phase 8: Polish, docs and evidence

- [ ] T007 [P] Update the docs: `README.md` (API section and "⚠️ Known limitations (v1)") and
  `specs/002-canvas-ui/contracts/openapi.yaml`. This touches no code, so it can run in parallel
  with T006.

  README additions:
  - **Where catalog values come from**: the management API with the operator's own token, and why
    not in-process. State the platform finding from R-1: on 2026.2 the in-process
    `%SYS.Task.Suspend`/`%OpenId` does not check `%Admin_Task`, and the product never uses it.
  - **Operator privilege**: `%Admin_Task` for reads and for suspend/resume. That `%Admin_Operate`
    alone suffices for reads is stated as *not proven* (read in the platform's source only).
  - **`status`/`lastError` semantics**: `"1"`, the platform text of a failed status, and
    `lastError` `"Success"`.
  - **Suspended tasks keep `nextRun`.**
  - **Deprecated aliases**: `isDestructive` and `lastRun`.
  - **Known limitations**: the list's lossy `Suspended`/`NextScheduled`, and the catalog classes
    of `compact-globals`/`defragment-globals`, which do not exist on 2026.2.
  - **`recentRuns`**: present per R-4, or absent with the reason if T006 was cut.

  OpenAPI changes, per [contracts/api-delta.md](contracts/api-delta.md):
  - update `CatalogTask`/`CatalogTaskDetail`;
  - remove `className` and `state`;
  - add `class`, `timePeriod`, `lastStarted`, `lastFinished`, `status`, `lastError`,
    `destructive`, `destructiveUnknown`, `origin`, `unavailable` and `recentRuns`;
  - mark `isDestructive` and `lastRun` `deprecated: true`;
  - add the 400/403/404/502 Problem responses with `platformStatus`/`platformInfo`;
  - change the suspend 200 body to `CatalogTask`.

  No new path. Run the suite and the frontend unit and e2e checks (48/48, 13/13) to confirm
  nothing else changed.

- [ ] T008 [P] Create `scripts/catalog-evidence/compare.sh`, reusing
  `scripts/validate-async-job-contract/lib/common.sh` and `lib/auth.sh` for preflight and login.
  This implements quickstart (a).
  - Credentials come only from `IRIS_USER`/`IRIS_PASSWORD`. No token is echoed, and headers are
    written as `<REDACTED>`.
  - Flow: product `GET /csp/sentai/api/v1/catalog/tasks` → platform list/single/info for every
    id → a per-field comparison per the data-model mapping. `status` is decoded by a one-line
    `docker exec … iris session` call to `$SYSTEM.Status.GetErrorText`; the script never
    re-implements it.
  - SC-002 check: undocumented keys, and missing keys that are not listed in `unavailable`.
  - US-1 scenario 4: item read equals the list item.
  - Output: `specs/006-task-catalog-api/evidence/a-field-compare.json` with rows
    `{taskId, field, product, platform, equal}`. Exit non-zero on any mismatch.

  Check with `bash -n` and `shellcheck` if available. The script can run in parallel with T006
  and T007 because it touches different files.

- [ ] T009 Run quickstart (a)–(f) on the real instance and record the evidence in
  `specs/006-task-catalog-api/evidence/` (depends on T001–T008).
  - The evidence files are `a-field-compare.json`, `b-origin.json`, `c-suspend-resume.json`,
    `d-refusal.json`, `e-timing.txt` and `f-recent-runs.json`.
  - Use temporary users and tasks only. Passwords are generated inside IRIS and never printed.
    Never suspend an instance task.
  - Before and after, record the `%SYS.Task` count and check that no temp user, role, task or
    history row remains.
  - Write the final backend count (baseline + ≈ 47, 2 adjusted, 0 removed) and the SC-001…SC-005
    results in `specs/006-task-catalog-api/evidence/README.md`.
  - Run the suite one last time.

**Cut order if time runs short** (from the plan):
1. Cut **T006** (history, US-5) first. Then `recentRuns` stays absent, T007's README says why, and
   quickstart (f) is skipped.
2. Cut the **evidence polish** of T009 next, while keeping T008 (the SC-001 script) and quickstart
   (a)–(e).

**T001, T002, T003 and T005 are never cut** (plan rows 1, 2 and 4).

---

## Dependencies & Execution Order

```
T000 (docs) ─ independent, do first
T001 ─┬─▶ T002 ─▶ T003 ─▶ T004 ──────────────┐
      └─▶ T005 ─▶ T006 (also needs T003) ────┼─▶ T009
          T007 [P], T008 [P] ────────────────┘
```

- **Story order**: US1 (T001–T002) → US2 (T003) → US4 (T004) → US3 (T005) → US5 (T006) →
  Polish (T007–T009).
- **T004 → T009 (analysis U2).** T009 depends on every task, including T004.
- US3 (T005) depends only on T001, so it can start as soon as US1's read exists. It stays after
  T004 here only because it follows the plan order, not because of a code dependency.
- **Same file, sequential**: `TaskService.cls` and `Dispatcher.cls` go T001 → T005 → T006.
  `TaskShape.cls` goes T001 → T002 → T003 → T006. `TaskFilter.cls` goes T001 → T004.

## Parallel Opportunities

- **T005** (`TaskService.cls`, `Dispatcher.cls`) runs alongside T002–T004 (`StepType`,
  `TaskShape`, `TaskOrigin`, `TaskFilter`, and their tests) once T001 is done. The file sets do
  not overlap.
- **T007** (docs) and **T008** (script) run alongside T006.

Example, after T001 is merged:

```text
Agent A: T002 → T003 → T004   (StepType, TaskShape, TaskOrigin, TaskFilter)
Agent B: T005                 (TaskService, Dispatcher)
```

## Implementation Strategy

1. **MVP = T000 + US1 (T001–T002).** `GET /catalog/tasks` and `GET /catalog/tasks/{id}` return
   only platform values, with catalog destructiveness. Stop and validate with quickstart (a) if
   needed.
2. **+ US2 (T003)** makes the 2026-09-25 case (`SentaiTask: 1#01..03`) visible from the product.
3. **+ US4 (T004)** makes the filters work on the corrected data.
4. **+ US3 (T005)** makes suspend/resume real.
5. **+ US5 (T006), docs (T007), script (T008), evidence (T009).**

Each step leaves the suite green, and no step adds an endpoint or changes the flow schema.

**Test estimate**: T001 11, T002 6, T003 8, T004 10, T005 7, T006 5, giving **+47** (≈ 40 in the
plan). Two are adjusted and none are removed.
