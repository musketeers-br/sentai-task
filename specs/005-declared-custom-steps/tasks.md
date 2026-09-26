# Tasks: Declared Custom Steps (backend)

**Input**: Design documents from `/specs/005-declared-custom-steps/` — [spec.md](spec.md) (source of
truth, Clarifications Q1 → A, Q2 → B, FR-001…FR-016), [plan.md](plan.md) rev. 2, [research.md](research.md)
(R-1…R-8), [data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (Constitution: TDD). Every task writes or adjusts the failing test **first**,
then the code, then runs the suite. No test method is deleted.

**Run the backend suite** (from the repo root):

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'X'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
halt
X
```

Baseline 122/122 when these tasks were written; **169/169 now that spec 006 has landed** (it added
`StepType.DestructiveByClass`, fixed `purge-audit-records`' class to `%SYS.Task.PurgeAudit`, and
added tests in `StepTypeTest` and `StepAvailabilityRuleTest`). Expected at the end ≈ 199 (169 + the
≈ 30 of this spec). Rebase T002/T013 edits of `StepType.cls` on 006's version; keep its tests. Frontend: `cd frontend && npm run generate:tokens && npm test` (48/48) and
`npx playwright test` (13/13, container up).

**Hard rules for every task** (Constitution II/III, plan):
- The class that runs is resolved **only** from the step's `type` via `sentai.registry.StepType`
  (the `XData Catalog`). Never read `step.customClass` in any execution path.
- Properties are set by iterating the **declared schema** (`parameters[].property`), never the keys
  of the step's JSON.
- No `Xecute`, no `MatchRoles:"%All"`, no credentials in code/fixtures/evidence. Temporary IRIS
  users get passwords generated inside IRIS (`$SYSTEM.Encryption.GenCryptRand`), never printed or
  stored; delete them afterwards.
- `FlowValidator.cls` and `WaveDispatcher.cls` are edited sequentially (never two tasks at once).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency on an incomplete task)
- **[Story]**: US1 run a declared step · US2 parameters checked · US3 nothing typed selects code ·
  US6 one identity per run · US4 shipped types · US5 native types again

---

## Phase 1: Setup

- [ ] T001 Create the fake task fixtures, one class per file in `tests/sentai/unittest/fixtures/`, package `sentai.unittest.fixtures`, each `Extends %SYS.Task.Definition` with a `Property Result As %String(MAXLEN = "")` (JSON text) where noted: `FakeOk.cls` (OnTask sets `Result = {"ok":true}` and returns `$$$OK`), `FakeFails.cls` (returns `$$$ERROR($$$GeneralError, "fake failure reason")`), `FakeThrows.cls` (`Set x = 1/0`), `FakeSwitchesNamespace.cls` (`Set $NAMESPACE = "%SYS"` then returns `$$$OK`, deliberately **without** restoring — mimics R-5), `FakeBigResult.cls` (Result = `{"items":[...]}` with 2000 entries of ~20 chars, i.e. > 8000 chars), `FakeWithParams.cls` (properties `Threshold As %Numeric`, `Label As %String`; Result echoes them). No test methods here; confirm the suite still loads and stays 122/122.

---

## Phase 2: Foundational (blocking for every story)

- [ ] T002 Extend the catalog in `src/sentai/registry/StepType.cls`. **Test first** in `tests/sentai/unittest/registry/StepTypeTest.cls`: every entry has `label` and `executor`; `GetExecutor("integrity-check") = "platform-api"`; the new entries exist with the schema of [data-model.md](data-model.md) §Entries. Then: add `label` and `executor` to all 7 entries; add `storage-headroom-check` (`sentai.steps.StorageHeadroomCheck`, category storage, in-process, parameters `[{"name":"minFreePercent","property":"MinFreePercent","type":"number","required":false,"default":10,"min":0,"max":100,"description":"…"}]`) and `db-size-report` (`sentai.steps.DatabaseSizeReport`, category verification, in-process, `parameters: []`) — **both `available: false` for now** (flipped only after real-instance proof, FR-007); leave `switch-journal` / `purge-task-history` untouched here (US5). Also declare `purge-audit-records`' `parameters: [{"name":"daysToKeep","property":"KeepDays","type":"integer","required":true,"min":1,"description":"…"}]` (`KeepDays` is `%SYS.Task.PurgeAudit`'s `%Integer` property, platform default 62, checked on the 2026.2 container) so the canvas can drop its local field (spec 007 BD-2); `available` stays `false`. Add helpers `GetExecutor(type)`, `GetParameterSchema(type) As %DynamicArray` (empty array when none), `DeclaresParameters(type) As %Boolean`, `IsInstalled(type) As %Boolean` (delegates to `ClassIsInstalled(className)`: `%Dictionary.CompiledClass.%ExistsId` **and** `$CLASSMETHOD(className,"%Extends","%SYS.Task.Definition")`; `IsInstalled` passes only the catalog's `class`; `0` for empty). Suite green.

- [ ] T003 Add to `src/sentai/model/StepRun.cls`: `Property result As %String(MAXLEN = 8000)`, `Property executedAs As %String(MAXLEN = 160)` (both additive), and `ClassMethod TransitionLocked(guid As %String, newState As %String, failureReason As %String = "") As %Status` that opens the StepRun by `GuidIndexOpen(guid, 4, .sc)` (exclusive lock + fresh read; lock timeout → return the error status unchanged), calls the existing `TransitionTo`, and releases by closing the object. **Test first** in `tests/sentai/unittest/model/StepRunLockTest.cls` (extends `sentai.unittest.SentaiTestCase`, run via `..DispatchUngated(..CreateSupportedFlow(...))`): (1) running → completed via `TransitionLocked` succeeds; (2) **race**: a `JOB` child calls `TransitionLocked(guid,"completed")` while the parent calls `TransitionLocked(guid,"failed","timed out")` — afterwards exactly one terminal state is persisted and the loser's status text contains `SentaiIllegalTransition`; (3) a stale in-memory object (opened before the other process wrote `failed`) can no longer overwrite it when the write goes through `TransitionLocked`. Suite green.

**Checkpoint**: catalog knows executors and schemas; terminal writes are single-winner.

---

## Phase 3: User Story 1 — Run a declared step inside a flow (P1) 🎯 MVP

**Goal**: a declared step (first one: `db-size-report`) runs on a WQM worker as the dispatcher and ends `completed`/`failed` with the platform's reason; its result and runner are visible.

**Independent test**: flow `01 db-size-report → 02 integrity-check` on `Default` dispatches and completes on the real instance; `GET /runs/{guid}` shows step 01 `result.databases` and `executedAs`.

- [ ] T004 [US1] Create `src/sentai/dispatch/InProcessExecutor.cls` with two methods. `ClassMethod RunTask(task As %SYS.Task.Definition, ByRef outcome) As %Status` — its own frame: `New $NAMESPACE`; `Try { Set sc = task.OnTask() }` `Catch ex { … }`; returns plain values in `outcome("ok")`, `outcome("reason")` (`$SYSTEM.Status.GetErrorText(sc)` verbatim or `ex.DisplayString()`), `outcome("result")` (task's `Result` property if it has one, else ""), `outcome("user") = $USERNAME`. `ClassMethod Run(stepRunGuid As %String) As %Status` — the worker entry: open StepRun/Step, read `class` **from the catalog by `step.type`** (never `customClass`), `$CLASSMETHOD(class,"%New")`, for each entry of `GetParameterSchema(type)` set `$PROPERTY(task, def.property)` from `step.parameters.%Get(def.name)` or `def.default`; call `RunTask`; then, **back in this frame (namespace IRISAPP)**, write `executedAs`, `result` (apply the truncation rule of [data-model.md](data-model.md) §Result size: drop elements from the end of the largest top-level array adding `"truncated":true,"omitted":n`; else `{"truncated":true,"originalLength":n}`) and `TransitionLocked(guid, "completed"|"failed", reason)` (retry 3× on lock timeout). **Tests first** in `tests/sentai/unittest/dispatch/InProcessExecutorTest.cls` using the T001 fakes through `RunTask`: ok, error status verbatim, exception text, namespace restored after `FakeSwitchesNamespace` (assert `$NAMESPACE = "IRISAPP"` after the call and `$D(^|"%SYS"|sentaiRun)` unchanged), `FakeBigResult` → stored JSON valid, ≤ 8000, `truncated:true`; and one `Run(guid)` test on a StepRun of `db-size-report` (after T005) asserting `executedAs = $USERNAME` and a terminal state in `IRISAPP`.

- [ ] T005 [P] [US1] Create `src/sentai/steps/DatabaseSizeReport.cls` (`Extends %SYS.Task.Definition`, read-only, `Property Result As %String(MAXLEN = "")`). First, **on the container**, confirm and record in [research.md](research.md) as **R-9** the 2026.2 way to list databases with size/free space from `IRISAPP` (e.g. the `%SYS.DatabaseQuery` free-space query) and its output for `_SYSTEM`. `OnTask` builds `{"databases":[{"name","directory","sizeMB","freeMB"}]}` into `Result`; any platform error is returned as the `%Status` (verbatim). **Test first** in `tests/sentai/unittest/steps/ShippedStepsTest.cls`: `RunTask` on a new `DatabaseSizeReport` → ok, `result.databases` non-empty and contains `IRISAPP_DATA`; nothing written (row counts of `sentai_model.*` unchanged).

- [ ] T006 [US1] Route in-process steps in `src/sentai/dispatch/WaveDispatcher.cls` (**sequential file**). **Tests first** in `tests/sentai/unittest/dispatch/DeclaredStepRunTest.cls`: (a) mixed flow `01 db-size-report → 02 integrity-check`, run created by `..DispatchUngated`, drive `StartStep` for 01 and wait (≤ 10 s) → 01 `completed` with `executedAs` set, 02 becomes eligible; (b) **timeout incl. queue time**: a StepRun of an in-process step set to `running` with `timeStarted` 2 min ago and step `timeoutMinutes = 1` → `SweepTimeouts(run)` makes it `failed` "timed out after 1 min"; `timeoutMinutes = 0` uses 60; (c) **SSE**: the run's `eventVersion` after (a) is greater than before (worker-written transitions bump it); (d) re-run of a failed in-process step while the run is live is queued and executed again. Then implement: in `StartStep`, if `GetExecutor(type) = "in-process"` → `TransitionLocked(guid,"running")`, `wm = $SYSTEM.WorkMgr.%New(,,category)` (unknown category → `failed` with the platform text, as today), `wm.Queue("##class(sentai.dispatch.InProcessExecutor).Run", guid)`, `wm.Detach(.token, 86400)`, never `Sync`; `platform-api` path unchanged. Add `ClassMethod SweepTimeouts(run)` (running in-process steps older than `timeoutMinutes` or 60 → `TransitionLocked(...,"failed","timed out after N min")`) and call it in `RunLoop` each pass; skip in-process steps in `PollInFlightSteps` (they have no `adminJobId`).

- [ ] T007 [US1] Expose the new data in `src/sentai/rest/Dispatcher.cls`: `ShapeStepRun` adds `executedAs` and `result` (parsed JSON object, `{}` when empty). **Tests first**: `tests/sentai/unittest/rest/StepTypeCatalogTest.cls` asserts `GET /catalog/step-types` entries carry `label`, `executor`, and `parameters` for in-process types; a run-read test (in `DeclaredStepRunTest.cls`) asserts `steps[].result.databases` and `steps[].executedAs`. Then, on the real instance, run quickstart (a) with `db-size-report` only; with the evidence recorded under `specs/005-declared-custom-steps/evidence/`, set `db-size-report` `available: true` in the catalog (FR-007) and adjust `StepTypeTest`.

**Checkpoint**: MVP — a declared step runs end to end as the dispatcher.

---

## Phase 4: User Story 2 — Parameters are checked before anything runs (P1)

**Goal**: missing / wrong-typed / out-of-range / unknown parameters and uninstalled declared classes are refused at validate, dispatch and schedule; no run is created.

**Independent test**: each violation refused on the 3 paths, naming step and parameter; 0 runs.

- [ ] T008 [US2] Add the schema rules to `src/sentai/validation/FlowValidator.cls` (**sequential file**; after T006). **Tests first** in `tests/sentai/unittest/validation/ParameterSchemaRuleTest.cls` (extend, keep existing methods), one test per code using `storage-headroom-check` / `db-size-report` steps: `PARAM_UNKNOWN` (`path`), `PARAM_TYPE_MISMATCH` (`minFreePercent: "ten"`), `PARAM_OUT_OF_RANGE` (150), `PARAM_REQUIRED` (use a schema entry with `required: true` built by a test-only helper that validates a step against a given schema array — the rule method takes the schema as an argument, so no production seam reads schemas from outside the catalog), and "declared class not installed" → `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` — test the class check through a helper `StepType.ClassIsInstalled(className)` (used by `IsInstalled` with the catalog's class only): `"sentai.steps.DoesNotExist"` → 0, `"sentai.unittest.fixtures.FakeOk"` → 1, `"sentai.unittest.SentaiTestCase"` (not a task) → 0 — stable regardless of which shipped classes exist; dispatch → `VALIDATION_FAILED` and no Run row; schedule → 422. Then implement: in the per-step loop, when `DeclaresParameters(type)` **and** `GetExecutor(type) = "in-process"` (so `purge-audit-records`, whose schema is declared for the canvas only — BD-2 — keeps exactly one error, its existing `PARAMETER_SCHEMA`): iterate the step's keys → `PARAM_UNKNOWN` for keys not in the schema; iterate the schema → required / type (`integer`: `$NUMBER(v,"I")` integral, `number`: `$ISVALIDNUM`, `boolean`: JSON boolean, `string`) / `min`/`max`; when `GetExecutor(type) = "in-process"` and `'IsInstalled(type)` → `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` with "its declared class is not installed". Messages per [contracts/api-delta.md](contracts/api-delta.md). Each `PARAM_REQUIRED` / `PARAM_TYPE_MISMATCH` / `PARAM_OUT_OF_RANGE` finding also carries `"parameter": "<name>"` (additive; `PARAM_UNKNOWN` carries the unknown key as `parameter`); one assertion per code (spec 007 BD-1). The existing `PARAMETER_SCHEMA` finding for `purge-audit-records` also gains `"parameter": "daysToKeep"` (additive; extend `ParameterSchemaRuleTest` with one assertion, keep its methods), and a test asserts a `purge-audit-records` step without `daysToKeep` yields exactly one finding.

---

## Phase 5: User Story 3 — Nothing the operator types selects code (P1)

**Goal**: legacy `custom` never executes; no path reads `customClass`.

**Independent test**: `custom` with `customClass = "%SYS.Task.SwitchJournal"` refused on 4 paths; journal file unchanged; flow loads unchanged.

- [ ] T009 [US3] **Tests only** (behaviour already guaranteed by spec 004 + T004/T006; this pins it): new `tests/sentai/unittest/validation/LegacyCustomStepTest.cls` — flow with one `custom` step `customClass: "%SYS.Task.SwitchJournal"`: validate → `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`; `Dispatch` → `VALIDATION_FAILED`, 0 runs; `ScheduleFlow` → 422, 0 native tasks; rerun of a failed custom StepRun (via `DispatchUngated`) → error with the code; `##class(%SYS.Journal.System).GetCurrentFileName()` identical before and after; `SaveGraph`/`ReadFlow` round-trip keeps `customClass`. Add a static guard test: the source of `sentai.dispatch.InProcessExecutor` and `WaveDispatcher` (read from `%Dictionary.MethodDefinition` implementations) contains no reference to `customClass`.

---

## Phase 6: User Story 6 — A run acts as one operator (P1)

**Goal**: one identity per run: mismatched run credential refused, re-run only by the dispatcher, in-process steps not schedulable, runner recorded.

**Independent test**: [quickstart.md](quickstart.md) (c) last paragraph and (e)5–6; plus `executedAs` in (a).

- [ ] T010 [US6] `IN_PROCESS_NOT_SCHEDULABLE` in `src/sentai/validation/FlowValidator.cls` `ValidateForSchedule` (**sequential file**; after T008): one error per step whose `GetExecutor(type) = "in-process"`, message per [contracts/api-delta.md](contracts/api-delta.md); additive with `DESTRUCTIVE_NOT_SCHEDULABLE`. **Test first** in `ParameterSchemaRuleTest.cls` (or a new `InProcessSchedulingRuleTest.cls`): flow with `db-size-report` → schedule 422 with the code, `NativeTaskCountFor(id) = 0`; `Validate` (not schedule) has no such error.

- [ ] T011 [US6] **R-8 first**: on the container, with two temporary users (generated passwords, deleted afterwards), call `/api/admin/login` for A and B, then `/api/admin/refresh` with bearer = A's access token and body = B's refresh token; record in [research.md](research.md) R-8 whether the response `sub` = B (owner of the refresh token). **If not, stop and report — FR-013 must be amended.** If yes, implement in `src/sentai/rest/Dispatcher.cls` `DispatchFlow`: when `runCredential.refreshToken` is present, **before** `WaveDispatcher.Dispatch`, POST `/api/admin/refresh` (via `AdminApiClient`) with the request token and that refresh token; non-200 → 401 problem carrying the platform's text verbatim (no run; no new code); `$ZCVT(sub,"U") '= $ZCVT($USERNAME,"U")` → 403 problem `RUN_CREDENTIAL_USER_MISMATCH: …`, no run; else store the **fresh** pair with `StoreRunCredential` after the run is created. Also in `RerunStep` (REST): open the run by guid; if `..CurrentUser() '= run.dispatchedBy` (case-insensitive) → 403 problem `RERUN_NOT_BY_DISPATCHER: …`. **Tests first** in `tests/sentai/unittest/rest/DispatchEndpointTest.cls`: script `/api/admin/refresh` on `AdminApiDouble` with `sub` of another user → 403 and 0 runs; with the same user → 202 and `^sentaiRun(guid,"%refresh")` = the scripted new refresh token; rerun as another user (set `%session("Username")`) → 403; as the dispatcher → 202.

---

## Phase 7: User Story 4 — Useful declared types out of the box (P2)

**Goal**: an evaluator has the storage headroom check (Embedded Python) and the size report.

**Independent test**: quickstart (a) and (b) on the real instance.

- [ ] T012 [US4] Create `src/sentai/steps/StorageHeadroomCheck.cls` (`Extends %SYS.Task.Definition`, read-only): `Property MinFreePercent As %Numeric [ InitialExpression = 10 ]`, `Property Result As %String(MAXLEN = "")`; `OnTask` gathers the locations **from the instance** — database directories (same query as R-9) plus `##class(%SYS.Journal.System).GetPrimaryDirectory()` — de-duplicated; for each calls `ClassMethod DiskFree(path) As %String [ Language = python ]` (`shutil.disk_usage`, returns `"ok <free%>"` or `"error <Type>: <msg>"`, as in R-3); builds `Result = {"minFreePercent":…,"locations":[{"path","freePercent","ok"}]}`; returns `$$$ERROR` naming **each** location below the threshold with its free % vs. the threshold, and each unreadable location with the Python error. **Tests first** in `tests/sentai/unittest/steps/ShippedStepsTest.cls`: `MinFreePercent = 0` → ok, every location `ok:true`; `MinFreePercent = 99.99` → error naming at least the journal directory; the Python method returns an error string (not an exception) for `/nonexistent/`. Then run quickstart (a) and (b) on the instance, record evidence, set `available: true` (FR-007) and adjust `StepTypeTest`.

---

## Phase 8: User Story 5 — Journal switch and task-history purge work again (P2)

**Goal**: `switch-journal` and `purge-task-history` run in-process with their schema; purge stays destructive.

**Independent test**: quickstart (e)1–3 as an administrator; (e)4 as an unprivileged user.

- [ ] T013 [US5] In `src/sentai/registry/StepType.cls` move `switch-journal` (`%SYS.Task.SwitchJournal`, `parameters: []`) and `purge-task-history` (`%SYS.Task.PurgeTaskHistory`, destructive, **pausable false**, `parameters: [{"name":"keepDays","property":"KeepDays","type":"integer","required":false,"default":30,"min":0,…}]`) to `executor: "in-process"`, still `available: false`. **Tests first / adjusted** (encode the new truth; no method deleted): `StepTypeTest` (executor, schema, purge-task-history `IsPausable = 0`); `tests/sentai/unittest/validation/StepAvailabilityRuleTest.cls` refusal matrix 6 → 5 types (20 refusals) once `switch-journal` is available, and → 4 types (16 refusals) when `purge-task-history` is flipped after spec 007 T009 (T016); new tests in `DeclaredStepRunTest.cls`: purge-task-history dispatch without confirmation → `CONFIRMATION_REQUIRED`; schedule → `DESTRUCTIVE_NOT_SCHEDULABLE` + `IN_PROCESS_NOT_SCHEDULABLE`. Then run quickstart (e)1–3 **and the mandatory (e)4** on the instance — for `purge-task-history` with a **temporary, uncommitted** `available: true` on the dev container only, reverted right after and recorded as such in the evidence — record evidence (journal file before/after, `executedAs`, `<PROTECT>` verbatim for the unprivileged user), and only then set `switch-journal` `available: true` (FR-007, FR-011); `purge-task-history` is set `available: true` only once spec 007 T009 is merged (see T016).

- [ ] T014 [US5] Adjust the three e2e specs that encoded "switch-journal not supported" (**test code only**, no UI change): `frontend/tests/us1-flow-composition.spec.ts` — remove `switch-journal` from the palette "not supported in v1" list; `frontend/tests/us2-inspector-validation.spec.ts` Q4 and `frontend/tests/us4-live-run.spec.ts` "Dispatch is refused…" — the canonical flow now has **1** error: `'1 error blocks scheduling (#04)'` (check the exact singular wording rendered by the status bar first) and no `#05` assertion. Run `npx playwright test` → 13/13.

---

## Phase 9: Polish & cross-cutting

- [ ] T015 Documentation in `README.md`: replace "Only integrity-check runs" in *Known limitations (v1)* with the available set; add a **Declared step types** section: the list with parameters, how to add one (a class extending `%SYS.Task.Definition` + one catalog entry, reviewed in a PR — never a typed class name), the identity model (runs as the dispatcher, `executedAs`, run credential must be the same user, only the dispatcher re-runs, in-process steps are not schedulable), required privilege for switch-journal / purge-task-history (`<PROTECT>` otherwise), timeout semantics (default 60 min, counts time waiting for a worker, work may continue after timeout/cancel), result truncation at 8000 chars. Update `specs/003-backend-objectscript/HANDOFF.md` open-items table (E-2 partially addressed by 005).

- [ ] T016 Real-instance acceptance: rebuild or `zpm load`, run the full backend suite (record the count, ≈ 199, 0 failures), frontend unit 48/48 and e2e 13/13, then execute [quickstart.md](quickstart.md) (a)–(e) including the **mandatory (e)4**, saving status + body per call (no tokens, no passwords) to `specs/005-declared-custom-steps/evidence/quickstart-http-<date>.json`; confirm residue: no `SentaiTask:` native tasks left, temporary users deleted. `purge-task-history` is flipped to `available: true` only after spec 007 T009 (typed confirmation in the dispatch dialog) is merged; until then T013's flip for that type is held and recorded here.

---

## Dependencies & Execution Order

```text
T001 ─► T002 ─► T003 ─┬─► T004 ─► T006 ─► T007 ─┐
                      └─► T005 [P] ──────────────┤
                                                 ├─► T008 ─► T010 ─► T011
                                                 ├─► T009
                                                 ├─► T012 (after T008 for PARAM tests)
                                                 └─► T013 ─► T014
                                                                    └─► T015 ─► T016
```

- `FlowValidator.cls`: T008 → T010 (sequential). `WaveDispatcher.cls`: T006 only. `Dispatcher.cls`: T007 → T011. `StepType.cls`: T002 → T007 (flag) → T012 (flag) → T013.
- US1 is the MVP; US2, US3, US6 follow (P1); US4 and US5 (P2) need US1's executor and US2's rules.

## Parallel examples

- After T003: **T004** (`InProcessExecutor.cls`) ‖ **T005** (`steps/DatabaseSizeReport.cls`).
- After T007: **T009** (tests only, new file) ‖ **T012** (`steps/StorageHeadroomCheck.cls`) while T008 → T010 run on `FlowValidator.cls`.

## Implementation strategy

- **MVP = T001–T007** (US1): one declared type runs end to end as the dispatcher — demonstrable.
- **Safety net = T008–T011** (US2, US3, US6): parameters, legacy lockdown, one identity. Never cut.
- **Value = T012–T014** (US4 Python, US5 natives). Cut order if time runs short: T013–T014 first,
  then the `result` persistence of T004/T007 (keep report output in the failure reason); never cut
  T004's locking/namespace frame, T008, T009.
- **Close = T015–T016**.
- 16 tasks (plan estimated ~10 coarser ones): the plan's tasks 4–5 and 9 were split so each ends in
  one observable behaviour (Constitution V).
