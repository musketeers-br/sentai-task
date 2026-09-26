# Implementation Plan: Declared Custom Steps (backend)

**Branch**: `005-declared-custom-steps` | **Date**: 2026-09-26 (rev. 2) | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-declared-custom-steps/spec.md` (Clarifications
2026-09-25: Q1 → A, Q2 → B). Rev. 2 applies the review of 2026-09-26 (identity on the real path,
single identity per run, locked terminal transitions, SSE, timeout semantics, namespace frame,
result size, test impact).

## Summary

Add **declared** step types to the closed catalog and run them **inside the platform**, on a Work
Queue Manager worker of the step's category, with the dispatching operator's own identity (Phase 0
R-1). Parameters are validated against a declared schema at the single validation gate. Ship two
read-only types (one in Embedded Python) and move `switch-journal` and `purge-task-history` from
their dead management-API endpoints to the same in-process path. A run has **one** identity: the
dispatch is refused when the run credential belongs to someone else, and only the dispatcher may
re-run a step. No UI, no new endpoint, no flow-schema change. Evidence: [research.md](research.md).

## Technical Context

**Language/Version**: ObjectScript + Embedded Python (`[ Language = python ]`), InterSystems IRIS 2026.2 (Build 221U)

**Primary Dependencies**: `%SYSTEM.WorkMgr` (named categories, `Queue`/`Detach`), `%SYS.Task.Definition`, `%SYS.Journal.System`, the platform's database query (sizes), Python stdlib `shutil`, `/api/admin/refresh` (run credential)

**Storage**: IRIS persistent classes; additive `StepRun.result` and `StepRun.executedAs`

**Testing**: `%UnitTest` via `zpm "test sentai-task -only"`; fake task objects in `tests/`; `AdminApiDouble` for the refresh call; Playwright e2e against the container

**Target Platform**: IRIS 2026.2 container `sentai-task-iris-1`, namespace `IRISAPP`

**Project Type**: web-service backend (REST API for the canvas)

**Performance Goals**: declared steps obey the same WQM ceilings as integrity checks; the run loop never blocks on a declared step (detached work)

**Constraints**: no new endpoint; no flow-schema change; no test removed; ~10 tasks before voting week

**Scale/Scope**: 6 source classes touched, 3 added; ~8 backend test classes and 3 e2e specs added/adjusted

## Identity model (review items 1, 2)

| Path | Who the platform sees | Source |
|---|---|---|
| `integrity-check` (management API) | owner of the **run credential** (`runCredential` refresh pair, E-1) | spec 002 E-1 fix |
| In-process step (worker) | `$USERNAME` of the process that queued it = the **`RunLoop` job** = the user of the REST request that dispatched | R-1 |
| Re-run of a step | queued by the **same `RunLoop`** (the dispatcher), not by whoever asked for the re-run | code: `RerunStep` only inserts a `queued` StepRun |
| Scheduled run | Task Manager's run-as user; no operator present | `ScheduledFlowTask` |

**Decisions**:

- **ID-1 — One identity per run: refuse on divergence.** When `/dispatch` carries a
  `runCredential`, the backend redeems it **before creating the run** (one `/api/admin/refresh`)
  and compares the `sub` of the returned pair with the request's `$USERNAME` (case-insensitive).
  Different → **403 `RUN_CREDENTIAL_USER_MISMATCH`**, no run; equal → the fresh pair becomes the
  run credential. Without `runCredential`, the run credential is the request's own token (same
  user by construction). Chosen over "document the divergence" because a run whose steps act under
  two identities cannot be explained to the operator (Constitution III, IV). The canvas signs the
  run in as the same user, so it is unaffected. *To verify at the start of task 5*: `sub` in the
  refresh response names the owner of the refresh token (R-8); if not, stop and amend FR-013.
- **ID-2 — Only the dispatcher re-runs.** `/rerun` is refused with **403
  `RERUN_NOT_BY_DISPATCHER`** when the requester's `$USERNAME` ≠ `run.dispatchedBy`, for every step
  type (a re-run executes under the dispatcher's identity/credential).
- **ID-3 — In-process steps are not schedulable.** `ValidateForSchedule` adds
  **`IN_PROCESS_NOT_SCHEDULABLE`** per in-process step: a scheduled run would execute them under the
  Task Manager's run-as user with no operator present — a new authority path this spec does not
  open. Keeps spec 004 D-2 ("scheduling is not a supported execution path") true.
- **ID-4 — Evidence of who ran it.** The worker records `$USERNAME` into `StepRun.executedAs`
  (exposed in the run read) — the per-step evidence for SC-006; quickstart (e)4 is **mandatory**.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | How the design complies | Status |
|---|---|---|
| **II Closed Capability Set** (FR-002) | The executed class is resolved **only** from the step's `type` through the compiled `XData Catalog`. No executor path reads `step.customClass`; legacy `custom` is `available: false` and refused before execution (validate, dispatch, schedule, rerun). Properties set on the task object come from iterating the **declared schema** (`parameters[].property`), never from the step JSON keys; an unknown key is `PARAM_UNKNOWN` and is never forwarded. `$CLASSMETHOD`/`$PROPERTY` receive catalog strings only. | ✅ |
| **III Delegated Authorization** (D-1, FR-012) | No new authorization and no identity assumption. Each in-process step runs as the dispatching operator (R-1; recorded per step in `executedAs`), and the platform decides at use time — R-5 showed `<PROTECT>` for an unprivileged operator, surfaced verbatim; quickstart (e)4 proves it over REST. A run has one identity: divergent run credential refused (ID-1); re-run only by the dispatcher (ID-2); no scheduled execution of in-process steps, where no operator is present (ID-3). Fallback kept from Q1 → A should a future platform break inheritance: only read-only types available, README says why. | ✅ |
| **IV Errors as Values** | Task call wrapped in `Try/Catch`; `%Status` errors and exceptions → `failed` + verbatim text; the loop never sees an exception; timeout is a value set by the loop; terminal transitions are locked and single-winner (no silent overwrite); a failed step fails its run. | ✅ |
| **I Layered Architecture** | Catalog = declared data; validator = rules; `InProcessExecutor` = edge to the platform task framework; `WaveDispatcher` routes by `executor` only. | ✅ |
| **V Verifiable Increments** | Every task ends in observable behaviour with its test. | ✅ |
| **Engineering: TDD / YAGNI / SoC** | Test first; no plugin discovery; executor separate from dispatcher; namespace isolation in its own frame. | ✅ |
| **Handoff constraints** | No `Xecute`; no `MatchRoles:"%All"`; no new unauthenticated web app; no credentials in code, fixtures or evidence (temporary test users get IRIS-generated passwords, never printed); no AI in the core. | ✅ |

**Post-design re-check**: unchanged — all ✅. No Complexity Tracking entries.

## Execution design (review items 3–7)

- **Routing**: `StartStep` looks at `executor`. `platform-api` → unchanged integrity-check path.
  `in-process` → (1) `TransitionTo("running")` under lock, (2) new WorkMgr group on the effective
  category, `Queue(InProcessExecutor.Run, stepRunGuid)`, (3) `Detach` — never `Sync`.
- **Locked terminal transitions (item 3)**: a single helper `StepRun.TransitionLocked(guid,
  state, reason)` opens the StepRun with `%OpenId(id, 4)` (exclusive lock + fresh read), applies
  `IsLegalTransition`, saves, releases. Used by the worker (completion) **and** by the loop's
  timeout sweep, so exactly one terminal state wins and terminal → terminal is refused. Lock
  timeout → the loop retries on its next pass; the worker retries 3× then records the loss.
- **SSE (item 4)**: events are **not** emitted by the loop. `StreamEvents` re-reads the Run every
  0.5 s and emits when `eventVersion` grew; `TransitionTo` bumps `eventVersion` with a row-level
  SQL update in whichever process writes. Worker-written transitions therefore produce events with
  no change; a test asserts `eventVersion` increases after a worker transition. (Browser SSE is
  still broken by gateway gzip — HANDOFF #4 — the canvas polls; unaffected.)
- **Timeout (item 5)**: counts from `running`, which is set **before** `Queue` → it includes time
  waiting for a worker under the category's ceilings. Chosen so a step that never gets a worker
  still ends. Documented in README and data-model. Default 60 min when `timeoutMinutes` = 0.
- **Namespace frame (item 6)**: `InProcessExecutor.Run(guid)` (in `IRISAPP`) → resolves the class
  from the catalog → calls `RunTask(task, .outcome)` whose **own frame** does `New $NAMESPACE`,
  sets properties, calls `OnTask` in `Try/Catch`, and returns plain values. Back in `Run`'s frame
  (namespace restored), it writes `result`, `executedAs` and the terminal transition. Test: a fake
  task that switches to `%SYS` → the StepRun is updated in `IRISAPP` and nothing is written to
  `^|"%SYS"|…`.
- **Result size (item 7)**: `result` ≤ 8000 chars. Over the limit: drop elements from the end of
  the largest top-level array until it fits, adding `"truncated": true` and `"omitted": <n>`; if it
  still does not fit, store `{"truncated": true, "originalLength": <n>}`. Always valid JSON; test
  covers both branches.

## Project Structure

### Documentation (this feature)

```text
specs/005-declared-custom-steps/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0: R-1…R-7 with real outputs (+ R-8 to verify in task 5)
├── data-model.md
├── quickstart.md        # (a)…(e), (e)4 mandatory
├── contracts/api-delta.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
src/sentai/
├── registry/StepType.cls           # XData: label, executor, parameters; new entries; helpers
├── validation/FlowValidator.cls    # PARAM_* rules; class installed; IN_PROCESS_NOT_SCHEDULABLE (sequential)
├── dispatch/WaveDispatcher.cls     # routing, timeout sweep, rerun-by-dispatcher (sequential)
├── dispatch/InProcessExecutor.cls  # NEW: Run(guid) + RunTask(task) frame
├── model/StepRun.cls               # + result, + executedAs, + TransitionLocked
├── rest/Dispatcher.cls             # runCredential redeem + sub check; rerun 403; ShapeStepRun fields
└── steps/                          # NEW
    ├── StorageHeadroomCheck.cls     # Embedded Python
    └── DatabaseSizeReport.cls

tests/sentai/unittest/
├── fixtures/Fake{Ok,Fails,Throws,SwitchesNamespace,BigResult,WithParams}.cls  # NEW (T001), one class per file
├── model/StepRunLockTest.cls                # NEW (T003): locked transitions, two-process race
├── registry/StepTypeTest.cls                # adjust: purge-task-history pausable=false, availability
├── validation/ParameterSchemaRuleTest.cls   # extend: PARAM_* + not installed + IN_PROCESS_NOT_SCHEDULABLE
├── validation/LegacyCustomStepTest.cls      # NEW (T009): legacy custom refused on 4 paths + static guard
├── validation/StepAvailabilityRuleTest.cls  # adjust: 6 → 5 → 4 unavailable types (purge-task-history last, after spec 007 T009)
├── dispatch/InProcessExecutorTest.cls       # NEW: outcomes, namespace frame, truncation, executedAs
├── dispatch/DeclaredStepRunTest.cls         # NEW: mixed flow, locked race, timeout, SSE version, rerun
├── rest/DispatchEndpointTest.cls            # extend: credential mismatch 403; rerun 403
├── rest/StepTypeCatalogTest.cls             # parameters in the catalog read
└── steps/ShippedStepsTest.cls               # NEW: size report; headroom lax / forced

frontend/tests/                              # test-only adjustments (no UI change)
├── us1-flow-composition.spec.ts             # palette "not supported" list: drop switch-journal
├── us2-inspector-validation.spec.ts         # Q4: canonical flow now 1 error (#04)
└── us4-live-run.spec.ts                     # dispatch refused: 1 error (#04)
```

**Structure Decision**: existing single-project layout; new `sentai.steps` package and a test
fixtures class. The executor is split: `Run(guid)` resolves the class **from the catalog**;
`RunTask(task, …)` receives an already-built object. Tests drive `RunTask` with fake task objects;
catalog-to-class resolution is tested on its own. No production method accepts a class name from
anywhere but the catalog.

## Implementation Sequence (input to /speckit-tasks)

`FlowValidator.cls` and `WaveDispatcher.cls` are touched sequentially.

| # | Task | FR / SC / review | Depends | Parallel |
|---|---|---|---|---|
| 1 | Catalog: `label`, `executor`, `parameters[]`; new entries; purge-task-history pausable=false; helpers. **StepTypeTest** first. | FR-001, FR-006 | — | — |
| 2 | Validator: `PARAM_*`; class not installed → `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`; `IN_PROCESS_NOT_SCHEDULABLE` on schedule. One test per code. | FR-005, FR-015, R-6, ID-3 | 1 | — |
| 3 | `GET /catalog/step-types` exposes the new fields (test asserts). | FR-006 | 1 | [P] with 2 |
| 4 | `StepRun`: `result`, `executedAs`, `TransitionLocked`. `InProcessExecutor` (`Run` + `RunTask` frame, truncation). Tests: ok / error / exception / namespace frame / truncation / **locked race** (two processes, one winner). | FR-003, FR-004, FR-016, items 3, 6, 7, ID-4 | 1 | [P] with 2, 3 |
| 5 | `WaveDispatcher` routing + detached queue + timeout sweep; `Dispatcher`: redeem `runCredential` + `sub` check (verify R-8 first), rerun-by-dispatcher; `ShapeStepRun` fields. Tests: mixed flow, timeout (incl. queue time), SSE `eventVersion` after worker write, credential mismatch 403, rerun 403. | FR-003, FR-004, FR-013, FR-014, items 2, 4, 5, ID-1, ID-2 | 2, 4 | — |
| 6 | `db-size-report` + test. | FR-008b | 4 | [P] with 7 |
| 7 | `storage-headroom-check` (Python) + tests (lax passes, forced fails naming locations). | FR-008a, SC-005 | 4 | [P] with 6 |
| 8 | Regression FR-002 / SC-002: legacy `custom` refused on 4 paths; old flows load; executor never reads `customClass`. | FR-002, SC-002 | 2, 5 | — |
| 9 | switch-journal & purge-task-history in-process: confirmation, `DESTRUCTIVE_NOT_SCHEDULABLE`, availability; adjust backend tests (StepTypeTest, StepAvailabilityRuleTest 24 → 20 refusals; → 16 once purge-task-history is flipped after spec 007 T009) and the 3 e2e specs that encoded "switch-journal not supported". | FR-011, FR-009, item 8 | 5 | — |
| 10 | Docs + evidence: README (types, how to declare one via PR, identity model ID-1…ID-4, required privilege for native types, timeout semantics incl. queue time, work continues after timeout/cancel, result truncation); run quickstart (a)–(e) incl. mandatory (e)4; record evidence. | FR-007, FR-012, SC-006 | all | — |

**Cut order if time runs short**: task 9 → result persistence of task 4 (keep report output in the
failure reason only; `executedAs` stays) → never cut 2, 4 (locking + frame), 8.

**Expected test count**: backend **122 → ~152** (rebased on spec 006 and its close-out: **178 → ~208**) (≈ +30: catalog 3, validator 7, executor 7,
dispatcher/REST 8, shipped 3, legacy 2); adjusted, none removed. Frontend e2e **13 → 13** with 3
specs adjusted (test code only); frontend unit **48 → 48** (verified: no unit test depends on
`purge-task-history` pausable or availability — fixtures there are local data).

## Risks

| Risk | Mitigation |
|---|---|
| Worker × loop race on the terminal state | `TransitionLocked` (`%OpenId(,4)` + fresh read + `IsLegalTransition`); two-process test, one winner |
| Late worker result after timeout/cancel | Terminal → terminal refused; loss recorded, never overwrites |
| Task leaves the process in `%SYS` | `New $NAMESPACE` in `RunTask`'s own frame; writes happen in the caller's frame; test proves no stray `%SYS` writes |
| Run credential of another user | Redeemed and compared at dispatch → 403 before a run exists (ID-1); depends on R-8 (`sub` semantics) — if `sub` cannot identify the owner, FR-013 cannot be met as written: stop and amend the spec before shipping |
| Re-run under someone else's identity | 403 unless requester = dispatcher (ID-2) |
| In-process steps executing in scheduled runs with no operator | `IN_PROCESS_NOT_SCHEDULABLE` (ID-3) |
| Timeout includes queue time | Documented; generous default (60 min) |
| Oversized report result | Truncation rule, always valid JSON |
| Operators without admin privilege | Platform `<PROTECT>` verbatim; README lists the privilege; proven in (e)4 |
| e2e specs asserting switch-journal unsupported | Adjusted in task 9 (test code only) |
| Database-size query differs on 2026.2 | Confirmed inside task 6 on the real instance before `available: true` |
| Suite leaves `running` runs (F-5) | New run tests use fakes finishing < 1 s and assert terminal state |

## Complexity Tracking

None — no constitution violations.
