---

description: "Task list for Backend ObjectScript — SentaiTask Orchestration Engine"
---

# Tasks: Backend ObjectScript — SentaiTask Orchestration Engine

**Input**: Design documents from `/specs/003-backend-objectscript/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/rest-mapping.md, contracts/sse-protocol.md

**Tests**: `plan.md` §Tests per layer and §Project Structure mandate a `sentai.unittest.*` package
(`model`, `validation`, `dispatch`, `rest`, `registry`), runnable via `zpm "test sentai-task -v -only"`,
and `quickstart.md` §Automated tests treats that suite as a required deliverable — not an optional
add-on. Test tasks are therefore included, one sub-phase per user story, mapped to the layer(s) that
story introduces.

**Organization**: Tasks are grouped by user story (per `spec.md`) to enable independent
implementation and testing of each story, following the plan's own §Recommended implementation
sequence (phases 1–9), which decomposes directly onto US1–US6.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US6)
- Every description includes the exact file path

## Path Conventions

Pure backend, single project, per `plan.md` §Project Structure:

- Production code: `src/sentai/<subpackage>/<Class>.cls`
- Tests: `tests/sentai/unittest/<subpackage>/<Class>Test.cls`
- `module.xml` at repository root (modified, not replaced)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Package skeleton and build registration — no business logic yet

- [X] T001 Create the `sentai` source tree: `src/sentai/rest/`, `src/sentai/model/`, `src/sentai/validation/`, `src/sentai/dispatch/`, `src/sentai/registry/`, `src/sentai/wqm/`, `src/sentai/catalog/`, and the mirrored test tree `tests/sentai/unittest/model/`, `tests/sentai/unittest/validation/`, `tests/sentai/unittest/dispatch/`, `tests/sentai/unittest/rest/`, `tests/sentai/unittest/registry/`
- [X] T002 Update `module.xml` to add `Resource Name="sentai.PKG"` and `UnitTest Name="/tests" Package="sentai.unittest" Phase="test"`, alongside the existing `dc.sample` entries (do not remove them)

**Checkpoint**: `zpm "load /home/irisowner/dev/ -v"` runs with the new package registered (compiles nothing yet — directories only)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Infrastructure every user story depends on — closed step-type catalog, HTTP entry
point with mandatory authentication, and the execution-resolution registry global. No user-story
endpoint is reachable until this phase compiles and its tests pass.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Implement `sentai.registry.StepType` as a compiled `XData` block in `src/sentai/registry/StepType.cls`, reproducing the seven-type catalog from `data-model.md §Step-type registry` (`integrity-check`, `compact-globals`, `defragment-globals`, `switch-journal`, `purge-audit-records`, `purge-task-history`, `custom`) with class, category, `destructive`, `pausable` (`pausable = true` only for the purge family), plus a query/lookup method other classes call — never a duplicated literal catalog
- [X] T004 [P] Create the `sentai.rest.Dispatcher` skeleton (`%CSP.REST` subclass) in `src/sentai/rest/Dispatcher.cls` with an empty `XData UrlMap`, `Parameter HandleCorsRequest`, and the CSP application `/csp/sentai/api/v1` configured without `Unauthenticated` and without `MatchRoles:"%All"` (HANDOFF constraint, FR-040)
- [X] T005 Implement `OnPreDispatch` in `src/sentai/rest/Dispatcher.cls`, validating the 60-second Bearer token per `research.md` R-002 (native validation, falling back to an internal `GET /api/admin/info` call if no native mechanism is confirmed on the target instance), rejecting with 401 on any missing/invalid/expired token, with no caching or reuse of the authorization decision across requests (FR-040, FR-041, NFR-006)
- [X] T006 [P] Implement the `^sentaiRun` resolution-registry write/read helper methods (used later by dispatch and by FR-043 lookups) in `src/sentai/dispatch/WaveDispatcher.cls` as a stub `ResolveRunStep()` method, matching the shape already contracted in `002-canvas-ui/contracts/data-model.md` (FR-043)
- [X] T007 [P] [Registry layer] Unit test in `tests/sentai/unittest/registry/StepTypeTest.cls`: confirms the seven types exist with the correct category, destructive flag, and pause capability (`pausable = true` only for `purge-audit-records`/`purge-task-history`)
- [X] T008 [P] [REST layer] Unit test in `tests/sentai/unittest/rest/AuthenticationTest.cls`: confirms any request to any registered route with no token returns 401, and that a valid-token request is not rejected by `OnPreDispatch` alone (FR-040, NFR-006)

**Checkpoint**: `sentai.registry.StepType` and `sentai.rest.Dispatcher` compile; `GET` to any route (even unmapped) returns 401 with no token; foundational tests pass — user story implementation can now begin

---

## Phase 3: User Story 1 - Persist and compose a flow (Priority: P0) 🎯 MVP

**Goal**: An operator composes a flow — name, steps, edges, joins, default category — saves it,
retrieves it byte-for-byte identical, and cannot introduce a cycle or a duplicate name.

**Independent Test**: Create the canonical five-step graph (three checks → purge → journal switch),
save, reload by id, compare structure; attempt a cycle-closing edge and confirm immediate rejection
(`quickstart.md` steps 1–2).

### Tests for User Story 1 ⚠️

- [X] T009 [P] [US1] Unit test in `tests/sentai/unittest/model/FlowTest.cls`: unique case-insensitive name index rejects a duplicate (FR-005); revision increments on every save, including geometry-only changes (FR-004)
- [X] T010 [P] [US1] Unit test in `tests/sentai/unittest/model/StepTest.cls`: `isDestructive` is always derived from `sentai.registry.StepType`, never writable from input, even if submitted (FR-010)
- [X] T011 [P] [US1] Unit test in `tests/sentai/unittest/model/EdgeTest.cls`: adding an edge that would close a cycle is rejected at the moment of the mutation, not only at save time (FR-007, NFR-003)
- [X] T012 [P] [US1] Unit test in `tests/sentai/unittest/model/JoinTest.cls`: a join entry exists for every target step with ≥2 incoming edges, carrying the `ALL_MUST_SUCCEED` policy (FR-008)
- [X] T013 [P] [US1] REST contract test in `tests/sentai/unittest/rest/FlowsTest.cls`: `POST /flows` returns 201 with `id`/`revision:1`; `GET /flows/{id}` returns an identical structure; `PUT /flows/{id}` against a stale revision returns 409; a name conflict returns 409; a cycle-closing edge on `PUT` returns 422 (FR-001–FR-007, `quickstart.md` steps 1–3)

### Implementation for User Story 1

- [X] T014 [P] [US1] Implement `sentai.model.Flow` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/Flow.cls`: `id`, `name`, `revision`, `savedAt`, `savedBy`, `defaultCategory`, `scheduleSpec`, `canvasGeometry` (opaque stream, FR-009), unique case-insensitive index on `name`
- [X] T015 [P] [US1] Implement `sentai.model.Step` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/Step.cls`: fields per `002-canvas-ui/contracts/data-model.md`, `parameters` as an embedded `%DynamicObject`, `isDestructive` computed on read from `sentai.registry.StepType` and rejected as writable input (FR-010, FR-011), index on `(flow, id)`
- [X] T016 [P] [US1] Implement `sentai.model.Edge` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/Edge.cls`: `flow`, `source`, `target`, index on `(flow, target)`, plus a `WouldCreateCycle(flow, source, target)` class method run on every insert/update (FR-007, NFR-003)
- [X] T017 [US1] Implement `sentai.model.Join` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/Join.cls`: unique index on `(flow, target)`, `policy` fixed to `ALL_MUST_SUCCEED` for v1, populated/maintained whenever a step reaches ≥2 incoming edges (FR-008) — depends on T016
- [X] T018 [US1] Implement `sentai.model.Flow:SaveGraph()` transactional save (steps + edges + joins + revision increment, one `TSTART`/`TCOMMIT` unit per `research.md` R-011) in `src/sentai/model/Flow.cls` — depends on T014, T015, T016, T017
- [X] T019 [US1] Add `UrlMap` routes `GET /flows`, `POST /flows`, `GET /flows/{flowId}`, `PUT /flows/{flowId}` to `src/sentai/rest/Dispatcher.cls`, delegating to `sentai.model.Flow` read/list/`SaveGraph()`, translating name-conflict/stale-revision to 409 and not-found to 404 per `contracts/rest-mapping.md §Errors` — depends on T018
- [X] T020 [US1] Add structural-validation call (acyclicity + required fields) as a precondition of `POST /flows` and `PUT /flows/{flowId}` in `src/sentai/rest/Dispatcher.cls`, returning 422 with `ValidationReport` on failure and persisting nothing (FR-007, `quickstart.md` step 3) — depends on T019; stubs `sentai.validation.FlowValidator` minimally (full validator completed in US2)

**Checkpoint**: User Story 1 fully functional and independently testable — `quickstart.md` steps 1–3 pass

---

## Phase 4: User Story 2 - Validate a flow (Priority: P0)

**Goal**: An operator requests explicit validation and receives a separated errors/warnings report
covering acyclicity, per-type parameter schema, namespace existence, the WQM category invariant, and
the database-directory mount precondition (warning only).

**Independent Test**: Validate a flow with a directly-injected cycle, a `custom` step with no
`customClass`, and a step whose mount precondition fails; confirm the first two are errors and the
third is a warning (`quickstart.md` step 4).

### Tests for User Story 2 ⚠️

- [X] T021 [P] [US2] Unit test in `tests/sentai/unittest/validation/AcyclicityRuleTest.cls`: a directly-injected cyclic graph produces a cycle error (FR-013)
- [X] T022 [P] [US2] Unit test in `tests/sentai/unittest/validation/CustomStepRuleTest.cls`: a `custom` step with no `customClass` always produces an error, never a warning (FR-011, FR-013)
- [X] T023 [P] [US2] Unit test in `tests/sentai/unittest/validation/ParameterSchemaRuleTest.cls`: each step type's parameters are validated against that type's schema; an out-of-schema parameter produces an error (FR-013)
- [X] T024 [P] [US2] Unit test in `tests/sentai/unittest/validation/NamespaceRuleTest.cls`: a step referencing a namespace that does not exist on the active instance produces an error (FR-013)
- [X] T025 [P] [US2] Unit test in `tests/sentai/unittest/validation/MountPreconditionRuleTest.cls`: a read-only mounted database directory produces a warning (never an error), worded in plain language naming the step (FR-014)
- [X] T026 [P] [US2] Unit test in `tests/sentai/unittest/validation/WqmInvariantRuleTest.cls`: a referenced WQM category violating its own nesting invariant produces an error (FR-013, US2 scenario 5)
- [X] T027 [P] [US2] REST contract test in `tests/sentai/unittest/rest/ValidateEndpointTest.cls`: `POST /flows/{id}/validate` returns `errors: []` for a fully valid flow and a populated report otherwise, never blocking on warnings alone (`quickstart.md` step 4)

### Implementation for User Story 2

- [X] T028 [US2] Implement `sentai.validation.FlowValidator` in `src/sentai/validation/FlowValidator.cls` with a single `Validate(flowId) As %DynamicObject` entry point producing the `ValidationReport` shape (`errors`, `warnings`), running rules in this fixed order: structural/schema (`flow-definition.schema.json`), acyclicity (via `sentai.model.Edge:WouldCreateCycle`), per-step-type parameter schema (via `sentai.registry.StepType`), namespace existence, WQM category nesting invariant, database-directory mount precondition (warning) — depends on T003, T016
- [X] T029 [US2] Wire `sentai.validation.FlowValidator.Validate` into `POST /flows/{flowId}/validate` in `src/sentai/rest/Dispatcher.cls`, and replace the T020 minimal stub used by `POST /flows`/`PUT /flows/{flowId}` with this full validator (FR-012, FR-015) — depends on T028, T020

**Checkpoint**: User Stories 1 AND 2 both work independently — `quickstart.md` steps 1–4 pass

---

## Phase 5: User Story 3 - Dispatch and execute a flow (Priority: P1)

**Goal**: A validated flow, when dispatched, returns a run identifier with every step already
carrying its own tracking identifier and queued time before the response is sent, executes respecting
edge dependencies with parallelism delegated to `%SYS.WorkQueueMgr`, and propagates join failures and
failure reasons verbatim.

**Independent Test**: Dispatch the canonical five-step flow; confirm all five steps have identifier +
queued time in the synchronous response; observe the three verification steps run in parallel while
the purge step waits for all three (`quickstart.md` steps 5–6).

### Tests for User Story 3 ⚠️

- [X] T030 [P] [US3] Unit test in `tests/sentai/unittest/model/StepRunTest.cls`: the six-state transition table rejects `completed → *`, `failed → *`, `cancelled → *`, `queued → running` with no GUID, and `queued → paused` (FR-022)
- [X] T031 [P] [US3] Unit test in `tests/sentai/unittest/model/RunTest.cls`: `eventVersion` starts at 0 and increments on every observable change (data-model.md, supports FR-025/FR-026)
- [X] T032 [P] [US3] Unit test in `tests/sentai/unittest/dispatch/WaveEligibilityTest.cls`: a step becomes eligible only once every source of its incoming edges reaches a terminal state satisfying `ALL_MUST_SUCCEED`; a fan-in step becomes eligible only after all three sources complete (FR-019, US3 scenario 3.1)
- [X] T033 [P] [US3] Unit test in `tests/sentai/unittest/dispatch/JoinFailurePropagationTest.cls`: any one of a join's required inputs failing transitions the target directly to `failed`, naming the failed input, with no new state introduced (FR-021, US3 scenario 4)
- [X] T034 [P] [US3] Unit test in `tests/sentai/unittest/dispatch/FailureReasonTest.cls`: `StepRun.failureReason` is stored and returned byte-for-byte from what the administrative-API test double returned — no summarization/rewording/truncation (FR-023)
- [X] T035 [P] [US3] REST contract test in `tests/sentai/unittest/rest/DispatchEndpointTest.cls`: `POST /flows/{id}/dispatch` on a valid flow returns 202 with all `StepRun`s already carrying `guid`/`timeQueued`; dispatch of a flow with a destructive step and no/mismatched typed confirmation returns 428 naming the pending step and starts nothing; dispatch of a flow with a structural error (including an escaped `custom`-with-no-class) is refused regardless of prior validation (FR-016, FR-017, FR-018, `quickstart.md` step 5)

### Implementation for User Story 3

- [X] T036 [P] [US3] Implement `sentai.model.Run` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/Run.cls`: fields per `002-canvas-ui/contracts/data-model.md` plus internal `eventVersion` (`%Integer`, never serialized), index on `flow`
- [X] T037 [P] [US3] Implement `sentai.model.StepRun` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/StepRun.cls`: index on `(run, stepId)`, and `TransitionTo(newState, ...)` validating against the static six-state transition table before writing — the sole writer of `state` (FR-022) — depends on T030 design
- [X] T038 [US3] Implement the dispatch transaction in `src/sentai/dispatch/WaveDispatcher.cls` (`Dispatch(flowId, confirmations) As %DynamicObject`): one `TSTART`/`TCOMMIT` creating `Run` + one `StepRun` per step (guid + queued time via `$SYSTEM.Util.CreateGUID()`) + `^sentaiRun` index entries, blocked by `sentai.validation.FlowValidator` (structural) and by missing/mismatched destructive confirmation (FR-016, FR-017, FR-018, NFR-002, NFR-004) — depends on T028, T036, T037, T006
- [X] T039 [US3] Implement wave-eligibility computation in `src/sentai/dispatch/WaveDispatcher.cls` (`ComputeEligibleSteps(runGuid)`): a step is eligible once every source of its incoming edges (`sentai.model.Edge`) is terminal and satisfies the join's `ALL_MUST_SUCCEED` policy (FR-019, FR-021) — depends on T038
- [X] T040 [US3] Implement `%SYS.WorkQueueMgr` enqueueing per eligible step under its WQM category, calling the same asynchronous administrative-API endpoint validated in `001-validate-async-job-contract` (HTTP 202 + `Location`), in `src/sentai/dispatch/WaveDispatcher.cls` — actual parallelism delegated entirely to the platform (FR-020) — depends on T039
- [X] T041 [US3] Implement the background dispatch loop (`JOB`ed after the dispatch transaction commits) in `src/sentai/dispatch/WaveDispatcher.cls`: polls step completion, calls `ComputeEligibleSteps` again after each terminal transition, propagates join failures to the target via `StepRun.TransitionTo('failed', ...)` naming the failed input (FR-021), copies `failureReason` verbatim from the administrative API response (FR-023) — depends on T040
- [X] T042 [US3] Add `UrlMap` route `POST /flows/{flowId}/dispatch` to `src/sentai/rest/Dispatcher.cls`, delegating to `WaveDispatcher.Dispatch`, returning 202 synchronously once the dispatch transaction commits and `JOB`ing the background loop — depends on T038, T041
- [X] T043 [US3] Add `UrlMap` routes `GET /runs` and `GET /runs/{runGuid}` to `src/sentai/rest/Dispatcher.cls`, reading `Run`/`StepRun`/`LogEntry`, reporting total run duration and sum of step durations as two separate values (FR-024) — depends on T036, T037

**Checkpoint**: User Stories 1–3 all work independently — `quickstart.md` steps 1–6 pass

---

## Phase 6: User Story 4 - Track and control execution (Priority: P1)

**Goal**: An operator observes step-state changes within 2 seconds (via SSE or 3s polling), pauses a
purge-family step in isolation, cancels an individual step or the whole run, and re-runs a failed
step.

**Independent Test**: Dispatch the canonical flow, observe ≥4 of the six states live; pause a
purge-family step in isolation; cancel another step without affecting siblings; confirm a pause
outside the purge family is explicitly refused (`quickstart.md` step 7).

### Tests for User Story 4 ⚠️

- [X] T044 [P] [US4] Unit test in `tests/sentai/unittest/dispatch/PauseControlTest.cls`: pausing a `purge-audit-records`/`purge-task-history` step transitions only that step to `paused`, with no effect on siblings; pausing any other type is explicitly refused, never silently ignored (FR-029, US4 scenarios 2–3)
- [X] T045 [P] [US4] Unit test in `tests/sentai/unittest/dispatch/CancelControlTest.cls`: cancelling an individual step affects only that step; whole-run cancel stops dispatch of not-yet-started steps and requests cancellation of running ones (FR-027, FR-028, US4 scenarios 4–5)
- [X] T046 [P] [US4] Unit test in `tests/sentai/unittest/dispatch/RerunControlTest.cls`: re-running a `failed` step creates a new `StepRun` identifier within the same run, starting from `queued`, with no effect on other steps (FR-030, US4 scenario 6)
- [X] T047 [P] [US4] REST contract test in `tests/sentai/unittest/rest/ControlEndpointsTest.cls`: `POST /runs/{runGuid}/steps/{stepGuid}/pause` on a non-pausable type returns 409 and the step remains `running`; the run/step cancel and rerun endpoints return the expected status per `contracts/rest-mapping.md §Errors` (`quickstart.md` step 7)
- [X] T048 [P] [US4] Integration test in `tests/sentai/unittest/rest/SseProtocolTest.cls`: an SSE connection emits `step-state-changed`/`log-entry` events with strictly increasing `eventVersion`, terminates with a `run-terminal` event when the run reaches a terminal state, and the concurrent 3s-polling `GET /runs/{runGuid}` never diverges from what the stream delivered (FR-025, FR-026, NFR-001, `contracts/sse-protocol.md`)

### Implementation for User Story 4

- [X] T049 [P] [US4] Implement `sentai.model.LogEntry` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/LogEntry.cls`: `run` (ref `Run`), `at`, `stepId` (nullable), `severity`, `message`, index on `(run, at)` (FR-025, supports `RunDetail.log`)
- [X] T050 [US4] Implement `WaveDispatcher.PauseStep`/`PauseRun`/`CancelStep`/`CancelRun`/`RerunStep` in `src/sentai/dispatch/WaveDispatcher.cls`: pause refused (409) for any type outside the purge family via `sentai.registry.StepType` (FR-029); whole-run pause suspends dispatch of not-yet-started steps; whole-run cancel additionally requests cancellation of running steps and blocks pending ones (FR-027); individual cancel/pause affects only the targeted `StepRun` (FR-028); rerun creates a new `StepRun` guid within the same run (FR-030) — depends on T037, T041
- [X] T051 [US4] Add `UrlMap` routes `POST /runs/{runGuid}/cancel`, `POST /runs/{runGuid}/pause`, `POST /runs/{runGuid}/steps/{stepGuid}/cancel`, `POST /runs/{runGuid}/steps/{stepGuid}/pause`, `POST /runs/{runGuid}/steps/{stepGuid}/rerun` to `src/sentai/rest/Dispatcher.cls`, delegating to T050, mapping the non-pausable case to 409 — depends on T050
- [X] T052 [US4] Implement the SSE method for `GET /runs/{runGuid}/events` in `src/sentai/rest/Dispatcher.cls`: keeps the connection open, polls `Run.eventVersion` every 500ms, emits `step-state-changed`/`log-entry`/`run-terminal` events per `contracts/sse-protocol.md`, checks `%response.IsClientConnected()` each loop iteration, and enforces a configurable maximum connection duration (default 10 minutes) (FR-025, FR-026, NFR-001) — depends on T036, T049
- [X] T053 [US4] Ensure every `StepRun.TransitionTo` call and `LogEntry` write increments `Run.eventVersion` within the same transaction (no divergence between SSE and the 3s-polling `GET /runs/{runGuid}` fallback per the spec's Edge Case), touching `src/sentai/model/StepRun.cls`, `src/sentai/model/LogEntry.cls`, `src/sentai/model/Run.cls` — depends on T037, T049

**Checkpoint**: User Stories 1–4 all work independently — `quickstart.md` steps 1–7 pass

---

## Phase 7: User Story 5 - Schedule and manage categories (Priority: P2)

**Goal**: A validated flow can be compiled into native platform scheduling entries (one task id per
step + next run time), and WQM category worker ceilings can be read/written with the nesting
invariant enforced and `affectedTaskCount` reported before a write.

**Independent Test**: Schedule a validated flow, confirm one task id per step + next run time; attempt
a category write violating the nesting invariant and confirm the block, with `affectedTaskCount`
shown before a valid write (`quickstart.md` steps 8–9).

### Tests for User Story 5 ⚠️

- [X] T054 [P] [US5] Unit test in `tests/sentai/unittest/model/CategoryTest.cls`: local mirror stays a passthrough read-optimization only — every write call goes to the administrative-API test double, never a local-only write (research.md, FR-033–FR-036)
- [X] T055 [P] [US5] Unit test in `tests/sentai/unittest/validation/CategoryInvariantTest.cls`: a category violating `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers` is rejected as an error, never a warning (FR-034)
- [X] T056 [P] [US5] REST contract test in `tests/sentai/unittest/rest/ScheduleEndpointTest.cls`: `POST /flows/{id}/schedule` on a validated flow returns 201 with one `taskId` per step + `nextRun`; scheduling a flow with any validation error is refused (FR-031, FR-032, `quickstart.md` step 9)
- [X] T057 [P] [US5] REST contract test in `tests/sentai/unittest/rest/WqmCategoryEndpointTest.cls`: `PUT /wqm/categories/{name}` with an invariant-violating body returns 422; a valid write reports `affectedTaskCount` before/with the write and does not affect any in-progress run (FR-034, FR-035, FR-036, `quickstart.md` step 8)

### Implementation for User Story 5

- [X] T058 [P] [US5] Implement `sentai.model.Category` (`%Persistent` + `%JSON.Adaptor`) in `src/sentai/model/Category.cls` as a local mirror only, unique index on `name`, never the source of truth (data-model.md)
- [X] T059 [US5] Implement `sentai.wqm.CategoryService` in `src/sentai/wqm/CategoryService.cls`: read/write as immediate passthrough to `/api/admin/v2/wqm-categories`, nesting-invariant check before any write (FR-034), `affectedTaskCount` computation against `sentai.model.Category`/`sentai.model.Step` usage (FR-035), no retroactive effect on runs already in progress (FR-036) — depends on T058
- [X] T060 [US5] Add `UrlMap` routes `GET /wqm/categories`, `GET /wqm/categories/{name}`, `PUT /wqm/categories/{name}` to `src/sentai/rest/Dispatcher.cls`, delegating to `sentai.wqm.CategoryService`, mapping the invariant violation to 422 (FR-033, FR-034, FR-035) — depends on T059
- [X] T061 [US5] Implement `/flows/{flowId}/schedule` in `src/sentai/rest/Dispatcher.cls`: blocks on any `sentai.validation.FlowValidator` error (FR-032), compiles each step into a native `%SYS.Task.Definition` entry per `research.md` R-007/OQ-1 (only no-incoming-edge steps start a run when firing natively; `WaveDispatcher` takes over from there), returns one `taskId` per step + `nextRun` (FR-031) — depends on T028, T038

**Checkpoint**: User Stories 1–5 all work independently — `quickstart.md` steps 1–9 pass

---

## Phase 8: User Story 6 - Query the step-type catalog (Priority: P3, reducible)

**Goal**: An operator (or the canvas) queries the closed step-type catalog for composition, and,
secondarily, the catalog of tasks already scheduled on the instance (including tasks not created by
this product), with suspend/resume.

**Independent Test**: Query the step-type catalog, confirm the seven types with correct
category/destructive/pausable; query the scheduled-task catalog and confirm non-product tasks also
appear, filterable by free text/namespace/state/destructive (independent test in spec.md US6).

### Tests for User Story 6 ⚠️

- [X] T062 [P] [US6] REST contract test in `tests/sentai/unittest/rest/StepTypeCatalogTest.cls`: the catalog read exposes all seven types with category, derived destructive flag, and pause capability; `custom` is listed as selectable but remains blocked by validation until a class is declared (FR-037, US6 scenarios 1–2)
- [X] T063 [P] [US6] REST contract test in `tests/sentai/unittest/rest/CatalogTasksTest.cls`: `GET /catalog/tasks` returns tasks not created by this product, filterable by free text/namespace/scheduling-state/destructive; `POST /catalog/tasks/{taskId}/suspend` toggles state reflected on the next read (FR-038, FR-039, US6 scenarios 3–4)

### Implementation for User Story 6

- [X] T064 [P] [US6] Add the step-type catalog read route (extension over `sentai.registry.StepType`, consumed by the canvas per `contracts/rest-mapping.md`) to `src/sentai/rest/Dispatcher.cls` (FR-037) — depends on T003
- [X] T065 [US6] Implement `sentai.catalog.TaskService` in `src/sentai/catalog/TaskService.cls`: passthrough read of the instance's scheduled-task catalog (including non-product tasks), filterable by free text/namespace/scheduling-state/destructive, plus suspend/resume (FR-038, FR-039) — first candidate to cut if time runs short, per spec.md
- [X] T066 [US6] Add `UrlMap` routes `GET /catalog/tasks`, `GET /catalog/tasks/{taskId}`, `POST /catalog/tasks/{taskId}/suspend` to `src/sentai/rest/Dispatcher.cls`, delegating to `sentai.catalog.TaskService` — depends on T065

**Checkpoint**: All six user stories independently functional — full `quickstart.md` passes

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Requirements that span every story and are not owned by a single user-story phase

- [X] T067 [P] Audit every class under `src/sentai/` to confirm no request parameter reaches `Xecute`, `$system.Process`, or any dynamic-execution form (Constitution II, HANDOFF constraint) and no credential is read from source or a versioned file (FR-042) — code review, no new file
- [X] T068 [P] Confirm the layered-architecture boundary by inspecting imports: `sentai.rest.Dispatcher` never touches `sentai.model.*` directly (always through `sentai.validation.FlowValidator`/`sentai.dispatch.WaveDispatcher`/service classes), and none of those import from `sentai.rest` (Constitution I) — code review, no new file
- [ ] T069 Run `zpm "test sentai-task -v -only"` and confirm every `sentai.unittest.*` suite (model, validation, dispatch, rest, registry) passes with the administrative-API test double, per `research.md` R-012
- [ ] T070 Run the full `quickstart.md` steps 1–9 end to end against a real IRIS instance, recording the outcome of Technical Done Criteria TD-01 (auth), TD-02 (per-step-type execution), TD-03 (SSE viability), TD-04 (scheduled ordering) in `specs/003-backend-objectscript/HANDOFF.md` or a follow-up note — resolves whether A-01–A-05 remain valid assumptions or must be escalated (plan.md §Assumptions, Open Questions, and Technical Done Criteria)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational — no dependency on other stories
- **US2 (Phase 4)**: Depends on Foundational; reuses `sentai.model.Flow/Step/Edge` from US1 (T014–T017) for its rule inputs, and replaces the US1 validation stub (T020) with the full validator — start after US1's models exist
- **US3 (Phase 5)**: Depends on Foundational and on US2's `FlowValidator` (dispatch blocks on structural errors, FR-018) and on US1's `Flow/Step/Edge/Join` — start after US1 and US2
- **US4 (Phase 6)**: Depends on US3's `Run/StepRun`/`WaveDispatcher` (control operations act on running dispatches) — start after US3
- **US5 (Phase 7)**: Depends on Foundational and US2's `FlowValidator` (schedule blocks on validation errors); independent of US3/US4 implementation details beyond reusing `WaveDispatcher` for post-schedule ordering — can start in parallel with US4 once US2 and US1 are done
- **US6 (Phase 8)**: Depends on Foundational (`sentai.registry.StepType`) only — can start in parallel with US3/US4/US5 once Foundational is done
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### Within Each User Story

- Tests written first, confirmed to fail before implementation
- Models before services/dispatch logic
- Services before REST endpoints
- Core state-machine/transaction logic before control/SSE additions

### Parallel Opportunities

- T003–T006 (Foundational) run in parallel — different files
- T007–T008 (Foundational tests) run in parallel with each other and after T003–T006
- T009–T013 (US1 tests) run in parallel; T014–T016 (US1 models) run in parallel
- T021–T027 (US2 tests) all run in parallel — independent rule files
- T030–T035 (US3 tests) run in parallel; T036–T037 (US3 models) run in parallel
- T044–T048 (US4 tests) run in parallel
- T054–T057 (US5 tests) run in parallel; T058 (US5 model) has no peer to parallelize with in its phase
- T062–T063 (US6 tests) run in parallel
- Once Foundational (Phase 2) completes, US6 (Phase 8) can be staffed in parallel with US1–US5 — it has no dependency on their models
- T067–T068 (Polish) run in parallel — pure review tasks

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Unit test in tests/sentai/unittest/model/FlowTest.cls"
Task: "Unit test in tests/sentai/unittest/model/StepTest.cls"
Task: "Unit test in tests/sentai/unittest/model/EdgeTest.cls"
Task: "Unit test in tests/sentai/unittest/model/JoinTest.cls"
Task: "REST contract test in tests/sentai/unittest/rest/FlowsTest.cls"

# Launch all models for User Story 1 together:
Task: "Implement sentai.model.Flow in src/sentai/model/Flow.cls"
Task: "Implement sentai.model.Step in src/sentai/model/Step.cls"
Task: "Implement sentai.model.Edge in src/sentai/model/Edge.cls"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: `quickstart.md` steps 1–2 pass independently
5. Deploy/demo if ready — a flow can be composed and persisted, even with no validation/dispatch yet

### Incremental Delivery

1. Setup + Foundational → foundation ready (auth, catalog, `^sentaiRun` helper)
2. US1 → persist/compose → **quickstart 1–3** (MVP)
3. US2 → explicit validation, reused by dispatch/schedule later → **quickstart 4**
4. US3 → dispatch + wave execution → **quickstart 5–6**
5. US4 → tracking + control + SSE → **quickstart 7**
6. US5 → scheduling + WQM categories → **quickstart 8–9**
7. US6 → catalogs (P3, first to cut if time runs short)
8. Polish → security/layering audit, full test suite, full quickstart, Technical Done Criteria review

### Parallel Team Strategy

With multiple developers, after Foundational:

- Developer A: US1 → US2 → US3 → US4 (the dependent chain, since dispatch needs validation and
  control needs dispatch)
- Developer B: US6 (fully independent of the chain) once `sentai.registry.StepType` exists
- Developer C: joins US5 once US1's models and US2's validator exist, working WQM categories and
  scheduling in parallel with US3/US4

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US1 and US2 are both P0 and both required before US3 can meaningfully block dispatch on
  validation (FR-018) — treat them as the joint MVP foundation, not strictly sequential-only
- US3 must precede US4: control operations (pause/cancel/rerun) act on a dispatch that US3 creates
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate a story independently against the matching `quickstart.md` step
- Two of the plan's flagged risks (R-002 token-validation mechanism, R-007/OQ-1 scheduled-run
  ordering) have the highest chance of forcing a revision of T005 and T061 respectively once
  validated against a real IRIS instance in T070 — do not treat their current implementation as
  final until T070 confirms it
