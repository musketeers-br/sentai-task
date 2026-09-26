# Feature Specification: Declared Custom Steps (backend)

**Feature Branch**: `005-declared-custom-steps`

**Created**: 2026-09-25

**Status**: Draft

**Input**: Widen what an operator can orchestrate beyond `integrity-check` (spec 004 D-1) without
breaking the Constitution: custom work enters the product as **declared** step types, reviewed in
the repository, never as a class name typed by the operator. Backend only; the canvas side is
spec 007.

## Clarifications

### Session 2026-09-25

- Q1 (D-1): If the executing process does not carry the dispatching operator's identity, what does
  this spec ship? → **A**: only **read-only** declared types are released; the identity under which
  they run is documented as a known limitation. Anything that changes the instance (including the
  native types of Q2) is released only if D-1 proves the operator's identity.
- Q2 (D-2): Re-enable native maintenance types through the same path? → **B**: yes, both
  `switch-journal` and `purge-task-history`, each only after being proven on the real instance
  **and** only if D-1 proves the operator's identity (they change the instance; see Q1).

## Context and Problem

After spec 004 only `integrity-check` executes. The other six catalog types are refused because
the management-API endpoints they relied on return 404 on IRIS 2026.2. During the contest's voting
week, an evaluator who installs SentaiTask and can only run integrity checks sees one trick.

The catalog already has a `custom` type with a free-text `customClass` field. It cannot be the
answer:

- it was wired to `/api/admin/v2/task/custom`, which returns 404 (`available: false` since 004);
- running a class whose name comes from operator input violates **Constitution II** (Closed
  Capability Set): "MUST NOT … reflective invocation of names taken from input".

The platform does run maintenance work through classes of its own task framework (the same
classes its Task Manager runs). What is missing is a **closed, reviewable** way for the product to
run such a class as a step, with validated inputs, inside the run it already orchestrates.

## Objective

An operator composes, validates and runs flows that mix `integrity-check` with **declared step
types**: each one a named capability that exists in the repository with its own parameter schema,
destructiveness and availability. Nothing the operator types ever selects code to run.

## Scope

### In scope

1. A declaration for custom step types in the existing closed catalog, including a **parameter
   schema** per type.
2. Execution of a declared type **inside the platform**, under the step's Work Queue Manager
   category, without the management API.
3. Validation of step parameters against the declared schema at the single validation gate.
4. The catalog read exposes each type's parameter schema (additive).
5. At least two declared types shipped with the product, useful and safe for evaluators — one of
   them implemented with the platform's **embedded Python** capability.
6. Re-enabling `switch-journal` and `purge-task-history` through the in-platform path, gated by
   D-1 and by proof on the real instance (D-2).
7. Proof of each newly available type on the real instance (IRIS 2026.2 container), as in 004.

### Out of scope

- Any UI (spec 007).
- Any field where an operator types a class name, code, script or expression; uploading code.
- Scheduling as a success path (spec 004 D-2 still holds; E-3 open).
- Cancelling the underlying work when a step is cancelled (F-2; cancel stays local).
- Pause for declared types (none is pausable in this spec).

## Decisions

### D-1: Identity — with whose authority does a declared step run? *(to be proven)*

Constitution III requires the platform to decide, at the moment of use, whether the operator may do
what the step does. A run is dispatched by an operator; today its steps call the management API
with that operator's credential. A declared step runs inside the platform instead, so its authority
is whatever user and roles the executing process holds.

**Requirement**: before any declared type is marked available, verify on the real instance which
user and roles the executing process holds when the run was dispatched by a given operator, and
record the evidence.

**Resolved (Clarifications Q1 → A)**: if the executing process carries the dispatching operator's
identity, every declared type may be released once proven. If it does **not**, only read-only
declared types are released, and the identity they run under is written in the README's known
limitations; types that change the instance stay `available: false`.

### D-2: Re-enable native maintenance types through the same path *(resolved: Q2 → B)*

`switch-journal` and `purge-task-history` (refused since 004 because their assumed management-API
endpoints return 404) move to the in-platform path, each re-enabled only when **both** hold:
it ran end to end on the real instance with evidence recorded, and D-1 proved the operator's
identity (both change the instance). `purge-task-history` is destructive: typed confirmation and
the not-schedulable rule apply unchanged. The other refused native types (`compact-globals`,
`defragment-globals`, `purge-audit-records`) stay unavailable.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Run a declared step inside a flow (Priority: P1)

An operator adds a declared step (e.g. the storage headroom check) to a flow next to integrity
checks, sets its parameters, validates, dispatches, and sees it finish as `completed` or `failed`
with the platform's own reason — exactly like any other step.

**Why this priority**: it is the whole point of the spec: more than one kind of work, safely.

**Independent Test**: A flow `storage-headroom-check → integrity-check` validates clean,
dispatches, and on the real instance the first step completes (or fails with its own message when
the threshold is set to force a failure), and the second waits for it per the existing join rules.

**Acceptance Scenarios**:

1. **Given** a flow whose step `01` is a declared type with valid parameters, **When** the
   operator validates it, **Then** the report has no errors for `01`.
2. **Given** that flow, **When** it is dispatched, **Then** step `01` runs under its WQM category,
   reaches `completed`, and a downstream step starts only afterwards.
3. **Given** a declared step whose work reports failure, **When** the run reaches it, **Then** the
   step is `failed`, its failure reason is the platform's message verbatim, downstream steps fail
   by the existing join policy, and the run ends `failed` — never `completed`.
4. **Given** a declared step with a timeout, **When** its work exceeds the timeout, **Then** the
   step is `failed` with a reason that says it timed out, and the run continues per join rules.
5. **Given** the step-type catalog, **When** it is read, **Then** each declared type appears with
   its parameter schema (name, type, required, default, description), its category, and its
   availability.

---

### User Story 2 — Parameters are checked before anything runs (Priority: P1)

An operator who leaves out a required parameter, or gives one of the wrong type, learns it at
validation — never mid-run.

**Why this priority**: Constitution II: inputs are data and MUST be validated against a declared
schema before the capability runs.

**Independent Test**: For each declared type, a flow with a missing required parameter and one
with a wrong-typed parameter are refused at validate, dispatch and schedule, naming the step and
the parameter; no run is created.

**Acceptance Scenarios**:

1. **Given** a declared step missing a required parameter, **When** validated, **Then** one error
   names the step and the parameter; dispatch and schedule are refused the same way.
2. **Given** a parameter of the wrong type (text where a number is declared), **When** validated,
   **Then** one error names the step, the parameter and the expected type.
3. **Given** a parameter not in the declared schema, **When** validated, **Then** it is reported
   (unknown parameter) and never reaches the executed work.
4. **Given** an optional parameter left out, **When** the step runs, **Then** the declared default
   is used.
5. **Given** a declared type marked destructive, **When** dispatched, **Then** the existing typed
   confirmation is required, exactly as for any destructive type.

---

### User Story 3 — Nothing the operator types selects code (Priority: P1)

The legacy `custom` type with its free-text class field never runs anything, and no other input
can choose what executes.

**Why this priority**: Constitution II is non-negotiable; this story is the guard rail.

**Independent Test**: Flows using the legacy `custom` type (with any class name) are refused on
validate, dispatch, schedule and rerun, still load and save unchanged, and no execution path
reads a class name from a step.

**Acceptance Scenarios**:

1. **Given** a saved flow with a legacy `custom` step naming any class, **When** it is read,
   **Then** it loads unchanged.
2. **Given** that flow, **When** validated, dispatched, scheduled or a step re-run, **Then** each
   is refused as not supported, as since spec 004.
3. **Given** any declared step, **When** it executes, **Then** the work that runs is determined
   solely by the step's type as declared in the repository.

---

### User Story 4 — Useful declared types out of the box (Priority: P2)

An evaluator installs SentaiTask and immediately has more than integrity checks to orchestrate.

**Why this priority**: the voting-week motivation; depends on stories 1–3.

**Independent Test**: On a fresh install, the catalog lists the shipped declared types as
available, and a demo flow using them runs to `completed` on the real instance.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the catalog is read, **Then** at least two declared types
   are available.
2. **Given** the **storage headroom check** (embedded Python), **When** it runs with a threshold,
   **Then** it measures the free space where the instance's databases and journal live and
   completes when every location is within the threshold, or fails naming each location over it
   and by how much.
3. **Given** the **database size report**, **When** it runs, **Then** it completes and its result
   (size per database) is visible in the step's outcome, changing nothing on the instance.
4. **Given** either shipped type, **When** it runs, **Then** it writes nothing outside what it
   declares (read-only for both).

---

### User Story 5 — Journal switch and task-history purge work again (Priority: P2)

An operator composes the classic maintenance wave — checks, then purge task history, then switch
journal — and it runs, instead of being refused as "not supported in v1".

**Why this priority**: the most recognizable maintenance operations; highest value for
evaluators. Gated by D-1 (they change the instance) and by proof on the real instance.

**Independent Test**: On the real instance, with D-1 proven, a flow `integrity-check →
purge-task-history → switch-journal` validates, asks for the typed confirmation for the purge,
runs to `completed`, and the platform shows a new journal file and a trimmed task history.

**Acceptance Scenarios**:

1. **Given** D-1 proved the operator's identity and both types were proven, **When** the catalog is
   read, **Then** `switch-journal` and `purge-task-history` are `available: true` with their
   parameter schemas (e.g. days of history to keep for the purge).
2. **Given** a flow with `purge-task-history`, **When** dispatched without the typed confirmation,
   **Then** it is refused naming the step; with it, the step runs.
3. **Given** a flow with `purge-task-history`, **When** scheduled, **Then** it is refused with
   `DESTRUCTIVE_NOT_SCHEDULABLE`, as for every destructive type.
4. **Given** `switch-journal` completes, **When** the operator looks at the platform, **Then** the
   current journal file changed.
5. **Given** D-1 did **not** prove the operator's identity, **When** the catalog is read, **Then**
   both types stay `available: false` and are refused exactly as in spec 004; the README says why.

### User Story 6 — A run acts as one operator (Priority: P1)

Whoever dispatches a run is the only authority behind every step of it: nobody else's credential
rides along, nobody else re-runs its steps, and no in-platform step runs later without an operator.

**Why this priority**: Constitution III on the new in-platform path; without it a run could mix
identities or run unattended under someone else's authority.

**Independent Test**: With two users, a dispatch whose run credential belongs to the other user is
refused; a re-run requested by the other user is refused; scheduling a flow with an in-platform
step is refused; every in-platform step's outcome names the dispatcher.

**Acceptance Scenarios**:

1. **Given** operator A dispatches with a run credential that belongs to operator B, **Then** the
   dispatch is refused with `RUN_CREDENTIAL_USER_MISMATCH` and no run is created.
2. **Given** a live run dispatched by A with a failed step, **When** B requests its re-run,
   **Then** it is refused with `RERUN_NOT_BY_DISPATCHER`; **When** A requests it, **Then** it is
   accepted.
3. **Given** a flow with an in-platform step, **When** it is scheduled, **Then** it is refused with
   `IN_PROCESS_NOT_SCHEDULABLE` for that step and no native task is created.
4. **Given** an operator without administrative privilege dispatches `switch-journal` and
   `purge-task-history`, **Then** both steps fail with the platform's denial verbatim and each
   outcome records that operator as who ran it.

### Edge Cases

- **Unknown parameter keys** are reported, never forwarded (User Story 2).
- **Declared class missing or not compiled** on the instance: the type is refused at validation as
  not supported on target, never failing mid-run.
- **Work raises an unexpected error** instead of returning a failure: the step is `failed` with
  the error text; the run loop keeps going (Constitution IV).
- **Work never returns**: the step's timeout applies; the step is `failed` (timed out). The
  underlying work may keep running (same limitation as cancel, F-2) — documented.
- **Timeout of 0 / not set**: a documented default applies (see Assumptions).
- **Rerun** of a failed declared step while the run is live: allowed, same rules as today.
- **Mixed flows**: declared steps, integrity checks and joins in one flow follow the existing wave
  and join rules unchanged.
- **Destructive declared type on /schedule**: refused with `DESTRUCTIVE_NOT_SCHEDULABLE`, and with
  `IN_PROCESS_NOT_SCHEDULABLE` as every in-platform type (both reported).
- **Timeout while waiting for a worker**: the timeout counts from when the step starts waiting for
  a worker, so a step that never gets one still ends as `failed` (timed out).
- **Headroom check on a location that cannot be read**: the step fails naming the location and the
  platform's reason, rather than skipping it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001 — Declaration.** A declared step type is an entry of the closed catalog carrying: type
  name, the platform class that implements it, category, destructive, pausable (false in this
  spec), available, and a parameter schema (per parameter: name, type, required, default,
  description). Declarations live only in the repository and change only through the normal
  change process.
- **FR-002 — No input selects code.** No execution path derives what to run from any value in a
  flow other than the step's type. The legacy `custom` type stays unavailable and never executes;
  its saved flows keep loading.
- **FR-003 — In-platform execution.** A step of a declared type runs inside the platform as a unit
  of work under the step's WQM category, invoking the declared class's task entry point with the
  step's validated parameters (declared defaults filling the gaps). It makes no management-API
  call.
- **FR-004 — Outcome.** The work's success/failure result decides `completed`/`failed`; on failure
  the reason is the platform's message verbatim. An unexpected error is caught at the execution
  edge and recorded the same way. Timeout ⇒ `failed` with a timed-out reason.
- **FR-005 — Parameter validation.** The single validation gate checks every declared step's
  parameters against its schema (required present, type matches, no unknown keys) and reports one
  error per violation naming step and parameter. Dispatch and schedule are refused accordingly.
- **FR-006 — Catalog exposes schemas.** The step-type catalog read includes each type's parameter
  schema, additively; existing fields unchanged.
- **FR-007 — Availability is proven.** A declared type is `available: true` only after it ran end
  to end on the real instance, with the evidence recorded (as in spec 004), and after D-1 is
  settled for it.
- **FR-008 — Shipped types.** The product ships at least: (a) **storage headroom check**,
  implemented with embedded Python, read-only, parameter: threshold of minimum free space;
  (b) **database size report**, read-only, no required parameters.
- **FR-009 — Destructive declared types** follow the existing typed-confirmation and
  not-schedulable rules with no new mechanism.
- **FR-010 — No regressions.** No flow-document schema change; all existing tests (backend
  122/122, e2e 13/13) pass, adjusted only where they encoded a now-false promise; no test deleted.
- **FR-011 — Native types via the in-platform path.** `switch-journal` and `purge-task-history`
  run through FR-003 instead of their unproven management-API endpoints, each with a declared
  parameter schema, and each `available: true` only under FR-007 **and** D-1 proving the
  operator's identity. `purge-task-history` stays destructive (FR-009).
- **FR-012 — Identity outcome is documented.** The evidence of D-1 (user and roles of the executing
  process for a run dispatched by a given operator) is recorded; if it is not the operator's, the
  README's known limitations say so, and only read-only declared types are available.

- **FR-013 — One identity per run.** When a dispatch carries a separate run credential, it is
  checked before the run is created; if it belongs to a user other than the one dispatching, the
  dispatch is refused (`RUN_CREDENTIAL_USER_MISMATCH`) and no run exists. Every step of a run —
  management-API or in-platform — therefore acts as the dispatching operator.
- **FR-014 — Only the dispatcher re-runs.** A re-run of a step is refused
  (`RERUN_NOT_BY_DISPATCHER`) when requested by anyone other than the operator who dispatched the
  run, because a re-run executes with the dispatcher's identity.
- **FR-015 — In-platform steps are not schedulable.** Scheduling a flow that contains an
  in-platform step is refused (`IN_PROCESS_NOT_SCHEDULABLE`, one per such step, no native task
  created): at fire time no operator is present, so the step would run under an identity nobody
  chose at use time. Spec 004 D-2 (scheduling is not a supported execution path) stays true.
- **FR-016 — Who ran it is recorded.** Each in-platform step records the user it ran as, visible
  with the step's outcome (evidence for SC-006).

### Key Entities

- **Declared step type**: a catalog entry as in FR-001; identified by its type name.
- **Parameter schema**: ordered list of parameter definitions (name, type, required, default,
  description) belonging to one declared type.
- **Step parameters**: the existing per-step `parameters` object, now validated against the schema
  of the step's type.
- **Step outcome**: existing `completed`/`failed` + failure reason; for report-style types, the
  result the work produced (e.g. sizes per database) visible with the step.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a fresh install, an evaluator can run a flow using at least **3 different kinds of
  step** (integrity check + 2 declared types) to `completed` on the real instance.
- **SC-002**: **0** paths execute code chosen by operator input: every attempt with the legacy
  `custom` type is refused on all 4 execution paths (validate, dispatch, schedule, rerun).
- **SC-003**: **100%** of parameter violations (missing, wrong type, unknown) in the test matrix
  are reported at validation, with **0** runs created for invalid flows.
- **SC-004**: A failing declared step always ends its run as `failed` with the platform's reason
  intact — **0** runs reported `completed` while a step failed.
- **SC-005**: The storage headroom check correctly reports every location under a forced
  threshold (threshold above the free space) and passes under a lax one, on the real instance.
- **SC-006**: The identity under which a declared step runs is recorded as evidence for each
  available declared type before release (D-1).
- **SC-008**: If D-1 proves the operator's identity, the classic wave (checks → purge task history
  → switch journal) runs to `completed` on the real instance; if not, **0** instance-changing types
  are available and the README states the reason.
- **SC-007**: Delivered within ~10 tasks, in time for the voting week.
- **SC-009**: **0** runs whose steps act under more than one identity: 100% of mismatched run
  credentials and third-party re-runs in the test matrix are refused, and every in-platform step
  outcome names the dispatcher.

## Assumptions

- The platform's task framework (the classes its own Task Manager runs, with a single task entry
  point returning success/failure) is the contract a declared class implements.
- The Work Queue Manager keeps being the parallelism mechanism: declared steps respect the same
  WQM category ceilings as integrity checks.
- Default timeout for a declared step with no timeout set: 60 minutes (documented).
- A report-style step's result is small (fits in the step's outcome); large outputs are out of
  scope.
- The embedded Python capability is available on the target instance (IRIS 2026.2 container).
- Both shipped types are read-only, so they are neither destructive nor require confirmation.

## Dependencies

- Spec 004 (availability flag, single validation gate, rerun guard).
- The E-1 run credential (spec 002 work) for the steps that still use the management API.
- Real IRIS 2026.2 container for FR-007 / SC-001, SC-005, SC-006.
- Spec 007 for any operator-facing UI of declared types.
