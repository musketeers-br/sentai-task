# Tasks: Backend Hardening — Reduce to Proven Truth

**Input**: Design documents from `/specs/004-backend-hardening/`
**Prerequisites**: [spec.md](spec.md) (source of truth, incl. Clarifications "minimum shippable scope"), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md), [quickstart.md](quickstart.md)

**Tests**: REQUIRED — Constitution "Test-Driven Development": every code task writes/adjusts the
failing test first, then the code, then runs the suite.

**Support set (D-1 amended)**: `integrity-check` only. The other 6 types — `compact-globals`,
`defragment-globals`, `switch-journal`, `purge-audit-records`, `purge-task-history`, `custom` —
are `available: false`.

**Run the suite**: `docker exec -it sentai-task-iris-1 iris session iris -U IRISAPP 'zpm "test sentai-task -v -only"'`
(baseline 86/86). Every task ends with the suite green; no test method is deleted (FR-008).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 = unsupported types blocked (FR-001..003); US2 = WQM categories (FR-004..006)

---

## Phase 1: Setup (docs reconciliation)

- [X] T001 Reconcile the stale design docs with the amended D-1 and the reduced quickstart (docs only, ~15 min):
  - `specs/004-backend-hardening/data-model.md`: availability table → `integrity-check` the only `available: true` row; the "Derived" line → "the only available type is neither destructive nor pausable".
  - `specs/004-backend-hardening/contracts/api-delta.md`: example message → `"Step type 'switch-journal' is not supported on the target platform in v1 (supported: integrity-check)"`.
  - `specs/004-backend-hardening/quickstart.md`: rewrite as three acceptance blocks only — (a) flow of 3 `integrity-check` steps (01, 02 roots → 03 join; fan-out/fan-in), `defaultCategory` and every `wqmCategory` = `Default` → `POST /validate` 200 `errors: []` → `POST /dispatch` 202 → `GET /runs/{guid}/events` until `run-terminal` with every step `completed`; (b) single-step `compact-globals` flow → validate reports `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`, dispatch 422, no run; (c) `integrity-check` flow with `wqmCategory: "NONEXISTENT"` → validate reports `CATEGORY_NOT_FOUND`, dispatch 422, no run. Move scheduling, >60 s / 401, real WQM write + read-back, defragment probe, destructive-schedule refusal and sanitation to a final `## Evidence / notes (not acceptance)` section. Delete the defragment step and the "best-effort" wording.
  - `specs/004-backend-hardening/plan.md`: Summary "5 unproven types" → "6"; T001 row `SupportedGraph()` → "01, 02 `integrity-check` roots → 03 `integrity-check` join, all `Default`"; T008 row drop "(incl. defragment outcome)" and "A–E" → "(a)–(c)"; remove the defragment risk row; Constitution V row "quickstart A–E" → "quickstart (a)–(c)".
  - `specs/004-backend-hardening/research.md`: R-007 item 2 → same all-`integrity-check` `SupportedGraph()`.

---

## Phase 2: Foundational (blocking — test scaffolding, pure refactor)

**Purpose**: after this phase the suite is still 86/86 and nothing behaves differently, but run
mechanics tests no longer depend on dispatch validation, so adding the availability and category
rules cannot break them.

- [X] T002 Build test scaffolding and split the dispatch gates from run creation (~45 min):
  - `src/sentai/dispatch/WaveDispatcher.cls`: extract, with the loop bodies moved verbatim, (1) `ClassMethod CheckConfirmations(flowId As %String, confirmationsArray As %DynamicArray, ByRef pendingStepId As %String) As %Boolean` — the existing FR-017 destructive-confirmation loop, returns 0 and sets `pendingStepId` on the first missing/mismatched confirmation; (2) `ClassMethod CreateRun(flowId As %String, confirmationsArray As %DynamicArray, dispatchedBy As %String, ByRef errorCode As %String, ByRef errorDetail As %String) As sentai.model.Run` — the existing `TSTART … TCOMMIT` block (Run + StepRuns + `^sentaiRun` index, `confirmedBy/At` for confirmed steps). `Dispatch()` becomes: `Validate` → `CheckConfirmations` (`CONFIRMATION_REQUIRED`) → `CreateRun`. Signatures and error codes of `Dispatch` unchanged.
  - `tests/sentai/unittest/AdminApiDouble.cls`: add `ClassMethod Put(urlPath, bearerToken, body, ByRef httpStatus, ByRef locationHeader) As %DynamicObject` — strip the query string to `basePath`, record `^sentaiTestDouble("put", basePath) = $LB(urlPath, body.%ToJSON())`, respond via `..Respond(basePath, "PUT", …)`.
  - `tests/sentai/unittest/SentaiTestCase.cls`:
    - in `OnBeforeOneTest`, after `Enable()`, script `GET /api/admin/v2/wqm-categories` → 200 with `{"result":[…]}` holding `Default`, `SQL`, `Utility` (`DefaultWorkers` 1, `MaxActiveWorkers` 2, `MaxWorkers` 0, `MaxTotalWorkers` 0, `AlwaysQueue` true — shape per spec 001 evidence 09) and `SENTAI.NIGHT` (1, 2, 4, 8, true);
    - add `Method SupportedGraphPayload(namePrefix As %String = "Supported") As %DynamicObject` — 3 `integrity-check` steps (01, 02 roots; 03 join target; edges 01→03, 02→03; join on 03), `defaultCategory` and all `wqmCategory` = `Default`, namespaces/dirs built like `CanonicalFlowPayload`;
    - add `Method CreateSupportedFlow(namePrefix As %String = "Supported") As %String` (mirror of `CreateCanonicalFlow`);
    - add `Method DispatchUngated(flowId As %String) As sentai.model.Run` — calls `WaveDispatcher.CreateRun(flowId, ..CanonicalConfirmations(), "tester", .ec, .ed)` and asserts `ec = ""`. Doc comment: "run-mechanics fixture; bypasses validation/confirmation gates on purpose".
  - Migrate run-mechanics tests (tests of cancel, pause, rerun, join, SSE, wave eligibility, failure reason, concurrency, step start — not of the gates) from `WaveDispatcher.Dispatch(id, …)` to `..DispatchUngated(id)`: `tests/sentai/unittest/dispatch/CancelControlTest.cls`, `ConcurrentTransitionTest.cls`, `FailureReasonTest.cls`, `JoinFailurePropagationTest.cls`, `PauseControlTest.cls`, `RerunControlTest.cls`, `StartStepTest.cls` (`DispatchWithCategory`), `WaveEligibilityTest.cls`; `tests/sentai/unittest/rest/ControlEndpointsTest.cls`, `SseProtocolTest.cls`. *(Done: also `model/RunTest.cls`, `model/StepRunTest.cls`, `rest/WqmCategoryEndpointTest.cls`, which dispatched the canonical flow too.)*
  - Run the suite: still 86/86.

**Checkpoint**: gates and run creation are separately callable; the double accepts PUT and serves categories; a supported fixture exists.

---

## Phase 3: User Story 1 — Unsupported step types are caught before anything runs (P1) 🎯 MVP

**Goal**: only `integrity-check` can reach the platform; the other 6 are refused on validate, dispatch, schedule and rerun; saved flows still load.

**Independent test**: `StepAvailabilityRuleTest` passes (24 refusals, 0 platform calls recorded by the double); quickstart block (b).

- [X] T003 [P] [US1] FR-001 availability in the catalog (~10 min). Test first: `tests/sentai/unittest/registry/StepTypeTest.cls` add `TestAvailabilityIsIntegrityCheckOnly` (`IsAvailable` = 1 only for `integrity-check`, 0 for the other 6, 0 for an unknown type); `tests/sentai/unittest/rest/StepTypeCatalogTest.cls` extend `TestCatalogExposesAllSevenTypesWithCategoryDestructiveAndPausable` to assert every entry has `available` with those values. Then `src/sentai/registry/StepType.cls`: add `"available": true` to `integrity-check` and `"available": false` to the other 6 entries in `XData Catalog`; add `ClassMethod IsAvailable(type As %String) As %Boolean` (same pattern as `IsPausable`: unknown → 0). No REST change — `ListStepTypes` returns `GetCatalog()` as-is.

- [X] T004 [US1] FR-002 + FR-003 blocking on all four paths (~40 min; depends on T002, T003). Tests first:
  - NEW `tests/sentai/unittest/validation/StepAvailabilityRuleTest.cls` (extends `SentaiTestCase`): for each of the 6 unavailable types build a single-step flow on `Default` (add `parameters.daysToKeep` for `purge-audit-records`, a `customClass` for `custom`) and assert — (1) `FlowValidator.Validate(id)` has exactly one `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` naming the step id, message contains the type; (2) `WaveDispatcher.Dispatch(id, confirmations, …)` returns "" with `errorCode = "VALIDATION_FAILED"` (never `CONFIRMATION_REQUIRED`, even for destructive types without confirmation) and no Run row is created; (3) `ValidateForSchedule(id)` has the error (plus `DESTRUCTIVE_NOT_SCHEDULABLE` for the two purge types) and `NativeTaskCountFor(id) = 0`; (4) on a run from `..DispatchUngated(id)`, fail the step (`TransitionTo("running")`, `TransitionTo("failed", "x")`) then `RerunStep` returns an error whose text contains `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` and no new StepRun exists. After the loop assert `$D(^sentaiTestDouble("posted"))=0` and `$D(^sentaiTestDouble("put"))=0` (no platform call; SC-001: 6 × 4 = 24 refusals). Plus: mixed flow (`integrity-check` 01 + `purge-audit-records` 02) → error only for 02; unknown type `"bogus"` → only `UNKNOWN_STEP_TYPE`; `custom` without `customClass` → both `CUSTOM_CLASS_REQUIRED` and `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`; `CreateSupportedFlow` → `errors: []`.
  - `tests/sentai/unittest/rest/FlowsTest.cls`: add `TestFlowWithUnavailableTypeSavesAndReadsUnchanged` (FR-003: `POST /flows` with the canonical payload → 201, `GET` returns identical steps).
  - `tests/sentai/unittest/dispatch/RerunControlTest.cls`: add `TestRerunOfUnavailableStepTypeIsRefused` (canonical run via `DispatchUngated`, fail step 04, rerun → error, still one StepRun for 04). The existing rerun tests target step 01 and stay unchanged.
  - Realign gate tests that asserted the canonical flow is valid (FR-008, no method deleted): `tests/sentai/unittest/rest/ValidateEndpointTest.cls` `TestFullyValidFlowReturnsNoErrors` → `CreateSupportedFlow`; `tests/sentai/unittest/rest/DispatchEndpointTest.cls` `TestValidDispatchReturns202WithAllStepsQueued` → `CreateSupportedFlow` (3 StepRuns), rename `TestMissingDestructiveConfirmationReturns428NamingStep` → `TestMissingDestructiveConfirmationNamesStep` asserting `CheckConfirmations(canonicalId, [], .p)` = 0 with `p = "04"`, and REST dispatch of the canonical flow now returns 422; `tests/sentai/unittest/rest/ScheduleEndpointTest.cls` 201 test → `CreateSupportedFlow` (3 taskIds), destructive test → replace the `HasNoErrors(Validate(id))` precondition with "`ValidateForSchedule` contains `DESTRUCTIVE_NOT_SCHEDULABLE` for 04"; `tests/sentai/unittest/validation/DestructiveSchedulingRuleTest.cls` — assert *presence* of `DESTRUCTIVE_NOT_SCHEDULABLE` (not error count), `TestDestructiveStepDoesNotAffectValidateOrManualDispatch` → assert `Validate` has no `DESTRUCTIVE_NOT_SCHEDULABLE` and `CheckConfirmations` accepts `CanonicalConfirmations()` / refuses `[]`, `TestNonDestructiveFlowPassesThisRule` → `SupportedGraphPayload`.
  - Then code: `src/sentai/validation/FlowValidator.cls` in rule 3 of the per-step loop: `If 'IsKnownType … UNKNOWN_STEP_TYPE` `Else { If 'IsAvailable(type) push {"stepId", "code":"STEP_TYPE_NOT_SUPPORTED_ON_TARGET", "message":"Step type '<type>' is not supported on the target platform in v1 (supported: integrity-check)"}` then the existing per-type parameter check `}`. `src/sentai/dispatch/WaveDispatcher.cls` `RerunStep`: after the `SentaiNotFailed` check, open the Step for `(run.flow, oldStepRun.stepId)` and if `'IsAvailable(step.type)` `Quit $$$ERROR($$$GeneralError, "STEP_TYPE_NOT_SUPPORTED_ON_TARGET: step '<id>' type '<type>' is not supported on the target platform in v1")`. REST already maps the status to 409 — no change in `src/sentai/rest/Dispatcher.cls`.
  - Run the suite: green; record the count. *(Done: 94/94. Also realigned `validation/MountPreconditionRuleTest.cls` `TestReadOnlyWarningDoesNotBlockValidation` → `SupportedGraphPayload`.)*

**Checkpoint**: US1 complete — quickstart block (b) holds in-process.

---

## Phase 4: User Story 2 — Built-in and real WQM categories work end to end (P1)

**Goal**: built-in categories pass the invariant; writes use the validated PUT contract; an unknown category is refused at validation.

**Independent test**: `CategoryInvariantTest`, `CategoryTest`, `WqmCategoryEndpointTest`, new `CategoryExistenceRuleTest` pass; quickstart block (c).

- [X] T005 [P] [US2] FR-005 zero is unbounded (~15 min; no file overlap with T003/T004/T006). Test first: `tests/sentai/unittest/validation/CategoryInvariantTest.cls` add one assertion per row of the invariant table in `data-model.md` (`1,3,0,0` ✓; `2,4,8,0` ✓; `1,2,0,5` ✗; `1,2,3,2` ✗; `0,0,0,0` ✓); `tests/sentai/unittest/validation/WqmInvariantRuleTest.cls` add `TestBuiltInDefaultWithZeroLimitsPasses` (mirror `Default` 1/2/0/0 via `sentai.model.Category.Mirror`, flow on `Default` → no `WQM_INVARIANT_VIOLATED`). Then `src/sentai/model/Category.cls` `SatisfiesInvariant`: treat `maxWorkers = 0` and `maxTotalWorkers = 0` as unbounded — `x ≤ y` is true when `y` is unbounded, false when `x` is unbounded and `y` is not, numeric otherwise; `defaultWorkers`/`maxActiveWorkers` unchanged. Suite green.

- [X] T006 [P] [US2] FR-004 WQM write contract (~20 min; depends on T002; no overlap with T003/T004/T005). Test first: `tests/sentai/unittest/model/CategoryTest.cls` and `tests/sentai/unittest/rest/WqmCategoryEndpointTest.cls` — change scripted responses from `("/api/admin/v2/wqm-categories/<name>", "POST", …)` to `("/api/admin/v2/wqm-category", "PUT", 200, "", "{}")`; add `TestWriteUsesValidatedPutContract` to `WqmCategoryEndpointTest` asserting `$LG(^sentaiTestDouble("put", "/api/admin/v2/wqm-category"), 1) = "/api/admin/v2/wqm-category?name=<name>"`, the recorded body has no `Name` key and numeric `MaxWorkers`/`MaxTotalWorkers`, and `$D(^sentaiTestDouble("posted", "/api/admin/v2/wqm-categories/<name>")) = 0`; keep the invariant-violation 422 test and assert nothing was recorded under `"put"`. Then `src/sentai/dispatch/AdminApiClient.cls` add `Put(urlPath, bearerToken, body, ByRef httpStatus, ByRef locationHeader)` mirroring `Post` (test-double branch → `AdminApiDouble.Put`; `req.Put(urlPath)`); `src/sentai/wqm/CategoryService.cls` `Write`: call `Put("/api/admin/v2/wqm-category?name="_$ZCONVERT(payload.name, "O", "URL"), …)`, drop `Name` from the body, set worker counts with `%Set(key, value, "number")` and `AlwaysQueue` with `"boolean"`, error text `"SentaiAdminApiError: wqm-category write returned HTTP <status>"`. Suite green.

- [X] T007 [US2] FR-006 category existence (~30 min; depends on T004 (FlowValidator, WaveDispatcher) and T006 (CategoryService)). Test first: NEW `tests/sentai/unittest/validation/CategoryExistenceRuleTest.cls` — with token `"test-token"`: step `wqmCategory: "NONEXISTENT"` → one `CATEGORY_NOT_FOUND` naming step and category; flow with no step categories and `defaultCategory` left at `SENTAI.DEFAULT` → one error per step; `CreateSupportedFlow` → no error; script `GET /api/admin/v2/wqm-categories` → 401 → every step reports `CATEGORY_NOT_FOUND` (fail closed, no exception); `Validate(id)` with no token → rule skipped (no `CATEGORY_NOT_FOUND`); `WaveDispatcher.Dispatch(id, [], "tester", .ec, .ed, .r, "test-token")` on the `NONEXISTENT` flow → `VALIDATION_FAILED`, no Run; `ValidateForSchedule(id, "test-token")` → error present. Add to `tests/sentai/unittest/rest/ValidateEndpointTest.cls` `TestUnknownCategoryReportedOverHttp` (set `%session("sentai.bearerToken") = "test-token"`, `POST /validate` → report has `CATEGORY_NOT_FOUND`; kill it after). Then code:
  - `src/sentai/wqm/CategoryService.cls` `List`: return `[]` when `httpStatus >= 300`, the body is not an object, or `result` is not an array (no exception).
  - `src/sentai/validation/FlowValidator.cls`: `Validate(flowId As %String, bearerToken As %String = "")`; when `bearerToken '= ""`, before the step loop build a name set from `CategoryService.List(bearerToken)`; in the loop, new rule after namespace: effective = `step.wqmCategory` or `flow.defaultCategory`; if not in the set push `{"stepId", "code":"CATEGORY_NOT_FOUND", "message":"WQM category '<name>' does not exist on the target platform"}`. `ValidateForSchedule(flowId, bearerToken = "")` forwards the token.
  - `src/sentai/dispatch/WaveDispatcher.cls` `Dispatch(..., ByRef validationReport, bearerToken As %String = "")` passes it to `Validate`. `src/sentai/dispatch/ScheduledFlowTask.cls` unchanged (no token → rule skipped at fire time, D-2).
  - `src/sentai/rest/Dispatcher.cls`: `ValidateFlow` → `Validate(flowId, ..CurrentToken())`; `DispatchFlow` → pass `..CurrentToken()` as the new last argument; `ScheduleFlow` → `ValidateForSchedule(flowId, ..CurrentToken())`.
  - Suite green. *(Done: 105/105. `AdminApiDouble.Get` now also records `^sentaiTestDouble("gets", path) = token` so the HTTP test can prove the credential was forwarded.)*

**Checkpoint**: US2 complete — quickstart block (c) holds in-process.

---

## Phase 5: Polish & cross-cutting (FR-007, FR-008)

- [ ] T008 Documentation, full suite and real-instance acceptance (~30 min; depends on T001–T007):
  - `README.md`: add `## Known limitations (v1)` after "What does it do": only `integrity-check` runs (other 6 types load but are refused with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`); scheduling — the D-2 wording verbatim from spec.md; platform calls made more than 60 s after dispatch fail with 401 (surfaced verbatim as the step's failure reason); step parameters (`databaseDirectory`, …) are not forwarded to the platform; flows must name an existing WQM category (default `SENTAI.DEFAULT` does not exist on a stock instance — use e.g. `Default`); no v1 type uses typed confirmation or pause.
  - `specs/003-backend-objectscript/HANDOFF.md`: add `## Resolution by spec 004` — E-1, E-3 "addressed by 004: documented, not fixed"; E-2 "addressed by 004: 6 types blocked, `integrity-check` only"; F-1, F-3, F-4 "fixed by 004 (T006, T007, T005)"; F-2, F-5 unchanged.
  - `specs/003-backend-objectscript/quickstart.md`: banner at the top — "Superseded for v1 by `specs/004-backend-hardening/quickstart.md`; kept as the T070 record."
  - FR-008: run the full suite; record the final count (86 existing + new) in `specs/004-backend-hardening/quickstart.md` "Evidence / notes"; confirm `git diff --stat tests/` shows no test class deleted.
  - Run `specs/004-backend-hardening/quickstart.md` blocks (a)–(c) on `sentai-task-iris-1` over HTTP (fresh token per block), save status + body per call (no tokens) to `specs/004-backend-hardening/evidence/quickstart-http-<date>.json`, and record any mismatch against the expected column (SC-005).

---

## Dependencies & Execution Order

```text
T001 (docs) ─┐
             ├─ T002 (scaffolding) ─┬─ T003 [P] ── T004 ──┐
             │                      ├─ T005 [P] ──────────┤
             │                      └─ T006 [P] ──────────┴─ T007 ── T008
```

- T001 has no code dependency; do it first so every later task reads current docs.
- T002 blocks everything that touches tests (fixtures, `DispatchUngated`, `AdminApiDouble.Put`).
- `src/sentai/validation/FlowValidator.cls`: T004 → T007 (sequential). T005 touches only `src/sentai/model/Category.cls`.
- `src/sentai/dispatch/WaveDispatcher.cls`: T002 → T004 → T007 (sequential).
- `src/sentai/wqm/CategoryService.cls`: T006 → T007 (sequential).
- US1 and US2 are independent once T002 is done, except T007 needs T004's `FlowValidator`/`WaveDispatcher` edits.

## Parallel Example

After T002, three developers (or sessions) can take, with no file overlap:

```text
T003 [US1] StepType.cls + StepTypeTest + StepTypeCatalogTest
T005 [US2] Category.cls + CategoryInvariantTest + WqmInvariantRuleTest
T006 [US2] AdminApiClient.cls + CategoryService.cls + CategoryTest + WqmCategoryEndpointTest
```

Then T004 (after T003), then T007 (after T004 + T006), then T008.

## Implementation Strategy

- **MVP = T001–T004**: after US1, no unproven type can reach the platform — the most visible false promise (E-2) is gone and quickstart block (b) holds.
- **Increment 2 = T005–T007**: WQM works against the real instance; quickstart (c) holds.
- **Close = T008**: docs + real-instance proof of (a)–(c).
- **Budget**: 15 + 45 + 10 + 40 + 15 + 20 + 30 + 30 ≈ **3 h 25 min**, 8 tasks. The overrun over ~3 h is T002: 10 test classes dispatch the canonical fixture (which contains `purge-audit-records`) and must move to `DispatchUngated` before the availability rule lands. With T003/T005/T006 in parallel the elapsed time is ≈ 3 h.
- **Out of scope (no tasks)**: token refresh, scheduled-run auth, parameter forwarding, proving `defragment-globals`, new endpoints, schema changes.
