# Feature Specification: Backend ObjectScript — SentaiTask Orchestration Engine

**Feature Branch**: `003-backend-objectscript`

**Created**: 2026-09-22

**Status**: Draft

**Input**: User description: "Define the expected behavior of the backend so that it persists
flows, validates them before use and before execution, executes them respecting dependencies
between steps, allows tracking runs and step runs, exposes the endpoints needed for composition,
execution and tracking, publishes execution events in near-real time, and honors the decisions
and constraints already approved in the project — without redefining the frontend, design, deploy
infrastructure, or decisions already closed (join policy, native scheduler, native GUID, derived
isDestructive, single instance, pause restricted to the purge family)."

## Context and Problem

SentaiTask is a visual orchestrator for InterSystems IRIS maintenance flows. Spec `002-canvas-ui`
defined the frontend composition experience and the data contracts that support it —
`openapi.yaml`, `data-model.md`, and `flow-definition.schema.json` — but it does not define the
system that actually stores, validates, and executes those flows. Without that system, the canvas
is a drawing tool with no effect: nothing the operator composes survives a page reload, no
dependency between steps is actually honored at execution time, and no run can be tracked or
controlled.

This spec defines the observable behavior that backend must deliver, in terms of what the system
does — not how it is built — so that the contracts already approved in `002-canvas-ui` stop being
just an interface promise and gain a real system behind them.

## Objective

Ensure that an operator can, end to end:

1. Compose a flow on the canvas and have it persisted reliably, with its steps, edges, joins, and
   default category preserved exactly as defined.
2. Validate that flow before scheduling or running it, receiving errors that block the action and
   warnings that do not.
3. Dispatch execution of the flow and trust that the execution order respects the dependencies
   declared by the edges, with parallelism delegated to the IRIS platform itself.
4. Track, in near-real time, the state of every step of the in-progress run, and control that
   execution (pause, cancel, re-run) within the limits already decided for v1.
5. Schedule a validated flow as a native platform task, and manage the Work Queue Manager worker
   ceilings that protect that execution.
6. Query the catalog of step types available for composing a flow.

All of this while fully preserving the decisions and contracts already approved — no reopening of
the join policy, the scheduling mechanism, identifier generation, the `isDestructive` rule, or the
single-instance scope.

## Scope

### In scope

- Persistence of flows and every element that composes them: steps, edges, joins, and the flow's
  default WQM category.
- Creation, listing, reading, and updating (with concurrency control) of flows.
- Explicit validation of a flow, both for general use and as a precondition for scheduling and
  dispatch.
- Dispatching execution of a flow, guaranteeing that the entire tracking structure (run and
  per-step identifiers) exists before the response to the operator.
- Execution respecting the order imposed by dependencies between steps (edges), with parallelism
  delegated to the platform's native concurrent execution mechanism.
- Querying the state of a run and of each step run within it, including the failure reason
  preserved exactly as produced by the platform.
- Publishing state-change events during execution, with a periodic-polling path for those who
  cannot maintain a continuous connection.
- Run- and step-control operations supported in v1: pause/cancel by wave (whole run), pause/cancel
  by individual step, and re-run a step that failed.
- Management of Work Queue Manager categories (read, edit, impact of a change).
- Scheduling a validated flow as a native platform task.
- Exposing the catalog of step types available for composition, and — as the lowest priority and
  reducible — the catalog of tasks already scheduled on the instance.
- Mandatory authentication on every exposed surface, and the absence of any credential embedded in
  code or in a versioned artifact.

### Out of scope

- Any frontend, canvas, visual component, or presentation technology behavior — that territory
  belongs to `002-canvas-ui`.
- Design system, themes, or any visual experience decision.
- Packaging, containers, deploy orchestration, or continuous integration/delivery pipelines.
- Run history screen and catalog screen on the frontend — only the data that would support them,
  where applicable, is in scope here.
- Any join policy other than `ALL_MUST_SUCCEED`. The data contract already declares other possible
  values (`PROCEED_ON_PARTIAL`, `MIN_SUCCEEDED`) for structural compatibility, but this spec does
  not require or guarantee behavior for them — only for `ALL_MUST_SUCCEED`.
- Mirror set, ECP, or any multi-instance topology configuration. The v1 solution assumes a single
  IRIS instance.
- Any functionality not backed by the already-approved contracts (`openapi.yaml`, `data-model.md`,
  `flow-definition.schema.json`) or by the decisions of `001-validate-async-job-contract`.
- Reopening any of the decisions already made (see the dedicated section below).

## Actors

- **Operator**: an authenticated user with credentials on the IRIS platform itself, responsible for
  composing, validating, scheduling, dispatching, and tracking flows. This is the only user type
  considered in this spec — there are no roles or permissions differentiated beyond those the
  platform itself already imposes.
- **IRIS Platform**: the system of record for native scheduling, concurrent execution,
  authentication/authorization, and all infrastructure state this backend does not duplicate.
- **Client (frontend or any authorized API consumer)**: consumes the endpoints and the event stream
  described in this spec; it is not the same as the operator, but it always acts on behalf of an
  authenticated operator.

## Decisions already made (treated as fixed — not reopened in this spec)

- **v1 join policy**: `ALL_MUST_SUCCEED`. When any required input of a join fails, the target step
  itself transitions to `failed`, with the reason naming the input that failed — no new state is
  introduced.
- **Scheduling**: done exclusively through the platform's own native scheduling mechanism. This
  backend never starts a private, in-process scheduler.
- **Execution identifiers (GUID)**: generated by the platform's own standard mechanism, not by a
  generator of this system's own.
- **`isDestructive`**: always derived from the step's type, from a closed, declared catalog. It is
  never an operator-editable field, even if submitted in a request.
- **Single instance**: the v1 solution assumes operation against a single platform instance; there
  is no requirement for coordination across multiple instances.
- **Pause**: in v1, the ability to pause an individual step exists only for the purge family of
  types (`purge-audit-records`, `purge-task-history`). Any other type that receives a pause request
  must refuse it explicitly, never silently ignore it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Persist and compose a flow (Priority: P0)

An operator composes a flow on the canvas — name, steps, edges, joins, and default category — and
expects saving to preserve exactly that structure, to be able to retrieve it later, and for an
attempt to introduce a cycle between steps to be rejected the moment it happens, not later.

**Why this priority**: Without reliable persistence, nothing else in this spec has anything to
stand on — it is the foundation validation, execution, and tracking are built on.

**Independent Test**: Create a flow with the canonical five-step graph (three checks converging
into a purge, followed by a journal switch), save, reload by id and compare structure byte for
byte; then try to add an edge that would close a cycle and confirm the immediate rejection.

**Acceptance Scenarios**:

1. **Given** a flow that does not yet exist, **When** the operator creates it with a valid name,
   steps, edges, and joins, **Then** the system assigns an identifier, sets the initial revision,
   and returns the fully persisted structure.
2. **Given** an existing flow, **When** the operator reads it by identifier, **Then** the returned
   structure — steps, edges, joins, default category, canvas geometry — is identical to the last
   one saved.
3. **Given** a saved flow, **When** the operator saves it again, even if only the canvas geometry
   changed, **Then** the revision is incremented.
4. **Given** a flow whose edge graph would be made cyclic by a new connection, **When** that
   connection is submitted, **Then** the system rejects it at the moment of submission, and the
   persisted graph remains acyclic.
5. **Given** two flows with the same name (case-insensitive), **When** the second is submitted,
   **Then** its creation is rejected due to a name conflict.
6. **Given** a flow loaded by an operator, **When** another operator saves it first and the
   original operator then tries to save without reloading, **Then** the second save is rejected due
   to a concurrency conflict, preserving the version that was saved first.

---

### User Story 2 — Validate a flow (Priority: P0)

An operator requests explicit validation of a flow and expects to receive a separate list of
errors (which block scheduling and dispatch) and warnings (which do not), including the
database-directory mount precondition check.

**Why this priority**: Without validation, an invalid flow would only be discovered by failing in
production — validation is what makes scheduling and dispatch trustworthy.

**Independent Test**: Validate a flow with a cycle introduced by directly editing the contract (not
through the composition flow), a `custom` step with no declared class, and a step whose mount
precondition is not satisfied; confirm that the first two appear as errors and the third as a
warning.

**Acceptance Scenarios**:

1. **Given** a structurally valid flow, with every step's parameters conforming to its type's
   schema, **When** the operator requests validation, **Then** the report returns with no errors.
2. **Given** a flow containing a `custom`-type step with no `customClass` defined, **When** the
   operator requests validation, **Then** the report contains an explicit error naming that step
   and requiring a class.
3. **Given** a flow whose step has a database directory mounted read-only, **When** the operator
   requests validation, **Then** the report contains a warning naming the step and describing the
   condition in plain words — never as a generic "invalid" — and validation as a whole does not
   block scheduling.
4. **Given** a flow whose edge set contains a cycle, **When** the operator requests validation,
   **Then** the report contains a cycle error and scheduling remains blocked until the cycle is
   removed.
5. **Given** a flow with a referenced WQM category that violates that category's own worker
   ceiling, **When** the operator requests validation, **Then** that violation appears as an error,
   not a warning.

---

### User Story 3 — Dispatch and execute a flow (Priority: P1)

An operator, with a flow validated and free of errors, dispatches its execution and expects the
response to already carry a run identifier, and every step to already have its own tracking
identifier and queued time — before any step even starts running.

**Why this priority**: This is the product's core value — without reliable dispatch and execution
that respects dependencies, composition and validation lead nowhere observable.

**Independent Test**: Dispatch the canonical five-step flow and confirm, in the synchronous
response, that all five steps already have an identifier and queued time; observe that the three
verification steps start in parallel and that the purge step only becomes eligible after all three
finish.

**Acceptance Scenarios**:

1. **Given** a validated flow with no errors, **When** the operator dispatches its execution,
   **Then** the response returns a run identifier and, before that response, every step of the
   flow already has its own identifier and a recorded queued time.
2. **Given** a flow containing a destructive step, **When** the operator dispatches without
   providing the required typed confirmation for that step, **Then** the dispatch is refused,
   naming which step has the pending confirmation, and no step of the flow starts.
3. **Given** a flow with three independent steps converging into a fourth (fan-in), **When** the
   dispatch occurs, **Then** the first three become eligible for execution simultaneously and the
   parallelism between them is resolved by the platform's native concurrent execution mechanism —
   this system does not implement its own parallel execution loop.
3.1 (variation). **Given** the same scenario, **When** all three steps complete successfully,
   **Then** the fourth step (the join's target) becomes eligible.
4. **Given** the join from the previous scenario, **When** at least one of the three inputs fails,
   **Then** the target step itself transitions to `failed`, with the reason naming the input that
   failed, without any new state being introduced.
5. **Given** a step that failed during execution, **When** the operator reads the step run,
   **Then** the failure reason appears exactly as the platform produced it — with no summary,
   rewording, or truncation.

---

### User Story 4 — Track and control execution (Priority: P1)

An operator tracks an in-progress run, watching each step transition through the six possible
states in near-real time, and uses the control operations available in v1 to pause or cancel at
the step or whole-run level, and to re-run a step that failed.

**Why this priority**: Together with dispatch, this is what makes execution accountable — without
tracking and control, a dispatched run is a black box.

**Independent Test**: Dispatch the canonical flow, observe at least four of the six states live via
querying the run, pause a purge-family step in isolation, cancel another step without affecting its
siblings in the same wave, and confirm that an attempt to pause a step outside the purge family is
explicitly refused.

**Acceptance Scenarios**:

1. **Given** an in-progress run, **When** the operator queries its state, **Then** every step run
   reports one of the six closed states (`queued`, `running`, `paused`, `completed`, `failed`,
   `cancelled`), and the most recent change that occurred on the platform reaches the client within
   2 seconds.
2. **Given** a running step of type `purge-audit-records`, **When** the operator requests its
   pause, **Then** only that step transitions to `paused`, without affecting the other steps in the
   same wave.
3. **Given** a running step of a type outside the purge family, **When** the operator requests its
   pause, **Then** the request is explicitly refused (never silently ignored), and the step
   continues running.
4. **Given** a running step, **When** the operator requests its individual cancellation,
   **Then** only that step transitions to `cancelled`; the other steps in the same wave continue
   normally.
5. **Given** the whole-run cancel button is triggered, **When** the operator confirms,
   **Then** dispatch of any not-yet-started step is stopped and cancellation is requested for
   whatever is already running.
6. **Given** a step that ended in `failed`, **When** the operator requests its re-run,
   **Then** a new step-run identifier is created within the same run, and the step becomes
   trackable again starting from `queued`.
7. **Given** a tracking session lasting more than 60 seconds, **When** the operator's access token
   expires mid-session, **Then** the renewal happens transparently and no state update is lost or
   delayed beyond the guaranteed 2 seconds.

---

### User Story 5 — Schedule and manage categories (Priority: P2)

An operator, with a validated flow, schedules its recurring execution as a native platform task,
and manages the Work Queue Manager worker ceilings of the categories that protect those
executions.

**Why this priority**: Scheduling and resource management are what make operation sustainable over
time, but they depend on composition, validation, and execution already working — hence the lower
priority than P0/P1.

**Independent Test**: Schedule a validated flow and confirm the return of one task identifier per
scheduled step plus the next run time; then try to save a WQM category that violates the nesting
invariant and confirm the block, with the affected-task count shown before attempting to save a
valid change.

**Acceptance Scenarios**:

1. **Given** a flow with no validation errors, **When** the operator requests its scheduling,
   **Then** the system returns one native task identifier per scheduled step and the next run time,
   using exclusively the platform's native scheduling mechanism.
2. **Given** a flow with at least one validation error, **When** the operator tries to schedule it,
   **Then** scheduling is refused.
3. **Given** an existing WQM category, **When** the operator reads its data, **Then** the system
   also reports how many scheduled tasks outside the current flow use that category.
4. **Given** a category change that violates
   `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`, **When** the operator tries
   to save, **Then** the save is blocked as a validation error, not a warning.
5. **Given** a valid category change, **When** the operator saves, **Then** the change does not
   affect any run already in progress.

---

### User Story 6 — Query the step-type catalog (Priority: P3)

An operator (or the canvas itself, on their behalf) queries which step types exist, with their
categories, destructive-flag, and pause capability, in order to compose a flow — and,
secondarily, queries which tasks are already scheduled on the instance, whether created by this
product or not.

**Why this priority**: This is explicitly the lowest priority — the step-type catalog is necessary
for composition to work at all (so it cannot be zero), but the catalog of already-scheduled tasks
is reducible if time does not allow.

**Independent Test**: Query the step-type catalog and confirm the seven declared types appear with
their correct category, destructive flag, and pause capability; secondarily, query the list of
tasks scheduled on the instance and confirm that tasks not created by this product also appear.

**Acceptance Scenarios**:

1. **Given** the closed catalog of step types, **When** an authorized consumer lists it,
   **Then** every type appears with its category, its destructive flag (derived, not editable),
   and whether it allows pausing.
2. **Given** the `custom` type, **When** it appears in the catalog, **Then** it is presented as
   selectable for composition, but its actual usability remains subject to the validation rule that
   always blocks it until a real class is declared.
3. **Given** tasks already scheduled on the instance, including tasks not created by this product,
   **When** the task catalog is queried, **Then** all of them appear, filterable by free text,
   namespace, scheduling state, and whether they are destructive.
4. **Given** a scheduled task, **When** its suspension is toggled, **Then** the new state is
   reflected on the next read of that task.

---

### Edge Cases

- What happens when the operator tries to schedule a flow with a validation error present? The
  scheduling is refused and the reason names the error and the affected step.
- What happens when a step's precondition stops being satisfied between validation and dispatch?
  The evaluation done at dispatch time is authoritative; the run reflects the actual outcome, not
  the result of an earlier validation.
- What happens when a destructive step's typed confirmation does not match the required name? The
  entire dispatch is refused, and the operator is told which step's confirmation was rejected —
  no step of the flow starts.
- What happens when a pause request arrives for a step type outside the purge family? The request
  is explicitly refused; the cancel action remains available for that step.
- What happens when a tracking session loses token renewal mid-run (for example, the instance
  restarted)? The client is told it needs to re-authenticate, rather than simply stopping to
  receive updates with no explanation.
- What happens when a WQM category's nesting invariant is already violated before any edit
  (pre-existing inconsistent data)? The read still returns the current values, flagging the
  violation as an error, but no save attempt is blocked until the operator actually tries to save.
- What happens when a join has more than two inputs? All of them are still evaluated under the same
  `ALL_MUST_SUCCEED` policy; any single one failing is already enough for the target to transition
  to `failed`.
- What happens when a `custom` step is dispatched with no `customClass` defined, having somehow
  escaped prior validation? Dispatch MUST also block it — the check is not exclusive to explicit
  validation.
- What happens when two operators try to save the same flow at the same time? Whoever saves first
  prevails; the second save is rejected due to conflict, preserving the integrity of the revision.
- What happens when the execution-events client cannot maintain a continuous open connection? The
  periodic query of the run's state reflects exactly the same state that would have been delivered
  by event, with no divergence.

## Requirements *(mandatory)*

### Functional Requirements

**Persistence and composition (P0)**

- **FR-001**: The system MUST allow creating a flow from a name, steps, edges, joins, and default
  category, assigning an identifier and fixing the initial revision.
- **FR-002**: The system MUST allow listing existing flows with identifier, name, revision,
  date/time and author of the last save, and next scheduled run (when any).
- **FR-003**: The system MUST allow reading an existing flow by its identifier, including the
  canvas's presentation geometry, responding with a clear error when the identifier does not
  exist.
- **FR-004**: The system MUST allow saving an existing flow, incrementing its revision on every
  save — even when only the canvas geometry changed.
- **FR-005**: The system MUST refuse the creation or save of a flow whose name already exists on
  another flow, ignoring case differences.
- **FR-006**: The system MUST refuse a save made against a revision that is no longer the most
  recent, to preserve the work of whoever saved first.
- **FR-007**: The system MUST reject, at the moment of submission, any edge that would introduce a
  cycle into the edge set — the check MUST run on every mutation, not only when saving or
  validating.
- **FR-008**: The system MUST maintain a join entry for every target step with two or more
  incoming edges, associating the policy in force with that step.
- **FR-009**: The canvas's presentation geometry MUST be stored as presentation data only — it
  MUST NOT influence execution order or the outcome of any validation.
- **FR-010**: The system MUST derive `isDestructive` for each step exclusively from its type, using
  a closed, declared catalog — it MUST NOT accept this value as operator input, even if submitted.
- **FR-011**: A `custom`-type step MUST be composable and persistable, but MUST always fail
  validation and dispatch as long as it has no real declared class — never a silently incomplete
  state.

**Validation (P0)**

- **FR-012**: The system MUST offer an explicit flow-validation action, returning a separate list
  of errors (which block scheduling and dispatch) and warnings (which do not block them).
- **FR-013**: Validation MUST check, at minimum: acyclicity of the edge graph, conformance of each
  step's parameters with its type's schema, existence of the referenced namespaces on the active
  instance, and conformance of the referenced WQM categories with their own nesting invariant.
- **FR-014**: Validation MUST include the database-directory mount precondition check (read-only)
  as a single fixed check — not a general precondition engine — reporting the result as a warning,
  never as an error that blocks scheduling.
- **FR-015**: The validation result is advisory: the precondition evaluation performed at dispatch
  time MUST take precedence over any earlier validation result.

**Dispatch and execution (P1)**

- **FR-016**: Dispatching a flow MUST create, before responding to the caller, a run and a tracking
  record (with its own identifier and queued time) for every step of the flow.
- **FR-017**: Dispatching a flow containing any destructive step MUST require a typed confirmation
  (database or namespace name) for each of those steps before starting any execution; the absence
  or mismatch of that confirmation MUST refuse the entire dispatch, naming the pending step.
- **FR-018**: Dispatching a flow containing any structural validation error (cyclic graph,
  out-of-schema parameter, `custom` type with no class) MUST be refused, regardless of whether an
  explicit prior validation was requested.
- **FR-019**: A step's eligibility for execution MUST derive exclusively from the edge graph — a
  step only becomes eligible once every source step of its incoming edges reaches a terminal state
  that satisfies the join policy in force.
- **FR-020**: Concurrent execution of simultaneously eligible steps MUST be delegated to the
  platform's own native concurrent execution mechanism — the system MUST NOT implement its own
  parallelism mechanism.
- **FR-021**: When the `ALL_MUST_SUCCEED` join policy is in force and any required input of a step
  fails, the target step itself MUST transition to `failed`, with the reason naming the input that
  failed — no new state is introduced.
- **FR-022**: Every step-run tracking record MUST follow the closed six-state machine (`queued`,
  `running`, `paused`, `completed`, `failed`, `cancelled`), with the transitions
  `completed → *`, `failed → *`, `cancelled → *`, `queued → running` without a prior identifier, and
  `queued → paused` explicitly forbidden.
- **FR-023**: A step's failure reason MUST be stored and returned exactly as produced by the
  platform — never summarized, reworded, or truncated.
- **FR-024**: The system MUST allow querying the list of runs and the detail of a specific run with
  all of its step runs, reporting the run's total duration and the sum of its steps' durations as
  two separate values, never collapsed into a single ratio.

**Tracking and control (P1)**

- **FR-025**: The system MUST publish state-change and log events during a run's execution, and
  MUST also offer an equivalent periodic-query path for clients that cannot maintain a continuous
  connection.
- **FR-026**: A state change that occurs on the platform MUST reach a subscribed or periodically
  polling client within 2 seconds.
- **FR-027**: The system MUST offer pause and cancel at the whole-run (wave) level: pause suspends
  dispatch of not-yet-started steps; cancel additionally requests cancellation of whatever is
  already running and prevents any pending step from starting.
- **FR-028**: The system MUST offer cancellation at the individual-step level, affecting only that
  step, with no impact on the other steps in the same wave.
- **FR-029**: The system MUST offer pause at the individual-step level only for the step types
  declared capable of pausing in v1 (the purge family); a pause request for any other type MUST be
  explicitly refused, never silently ignored.
- **FR-030**: The system MUST allow re-running a step that ended in `failed` within the same run,
  creating a new tracking record for that step with no effect on the others.

**Scheduling and categories (P2)**

- **FR-031**: The system MUST allow compiling a validated flow (no errors) into native platform
  scheduling entries, returning one task identifier per scheduled step and the next run time — it
  MUST NOT start a private, in-process scheduler.
- **FR-032**: The system MUST refuse scheduling of a flow that still carries any validation error.
- **FR-033**: The system MUST allow reading and updating the worker ceilings of a Work Queue
  Manager category (default workers, max active workers, max workers, max total workers, and the
  always-queue flag).
- **FR-034**: The system MUST refuse writing a category whose values violate
  `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`, treating that violation as an
  error, never a warning.
- **FR-035**: Before accepting a category write, the system MUST report how many scheduled tasks
  outside the current flow use that category.
- **FR-036**: A category change MUST NOT affect the behavior of any run already in progress at the
  time of the change.

**Catalog (P3, reducible)**

- **FR-037**: The system MUST expose the closed catalog of available step types, each with its
  category, derived destructive flag, and pause capability.
- **FR-038**: The system SHOULD expose the catalog of tasks already scheduled on the instance —
  including those not created by this product — filterable by free text, namespace, scheduling
  state, and whether they are destructive. This capability is the first candidate for reduction if
  delivery time does not allow the full scope.
- **FR-039**: The system SHOULD allow suspending or resuming a task scheduled on the instance, with
  the same reducible priority as FR-038.

**Cross-cutting / Security**

- **FR-040**: Every surface exposed by this system MUST require operator authentication; no
  endpoint MUST be reachable anonymously.
- **FR-041**: The system MUST NOT cache, infer, or reuse an authorization decision across requests
  — every privileged action is authorized by the platform at the moment it is performed.
- **FR-042**: No credential, token, or secret MUST be embedded in source code or in any versioned
  artifact; credentials MUST be supplied exclusively through the platform's own runtime
  configuration and session mechanisms.
- **FR-043**: The system MUST maintain a way to resolve, in a single lookup, an execution
  identifier observed in the platform's own operational records back to the run and step it
  belongs to.

### Non-Functional Requirements *(observable)*

- **NFR-001**: A state change that occurs on the platform during a run is observable by a client
  (via event or periodic query) within 2 seconds, for the entire duration of the run, including
  across at least one access-token renewal.
- **NFR-002**: The response to dispatching a flow is synchronous with respect to the creation of
  tracking records — no step exists without its identifier and queued time at the moment the
  response reaches the operator.
- **NFR-003**: Acyclicity of the edge graph is guaranteed on every mutation, not only at periodic
  checkpoints — there is no persisted intermediate state in which the graph is cyclic.
- **NFR-004**: Every destructive action dispatched records, in an auditable way, which operator
  provided the confirmation and when.
- **NFR-005**: The system operates correctly against a single platform instance, without assuming
  coordination, replication, or failover across multiple instances.
- **NFR-006**: No request to any exposed endpoint is served without valid operator authentication;
  every unauthenticated attempt is refused consistently and without leaking information about
  whether the requested resource exists.

### Business Rules

- The v1 join policy is fixed: `ALL_MUST_SUCCEED`. Any required input that fails makes the target
  step fail, naming the responsible input.
- `isDestructive` is never input data — it is always derived from the step's type from a closed
  catalog.
- The only precondition type evaluated in v1 is the fixed database-directory mount check
  (read-only); there is no general precondition engine.
- The ability to pause an individual step, in v1, exists only for the purge family of types; any
  other type explicitly refuses a pause request.
- Scheduling always goes through the platform's native mechanism; this system never keeps its own
  scheduling clock.
- Execution identifiers (GUID) are always generated by the platform's own standard mechanism.
- The v1 solution assumes a single platform instance — no business rule here assumes coordination
  across instances.
- A Work Queue Manager category is only written if it respects
  `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`; the violation is always an
  error, never a warning.
- A category change never retroactively affects a run already in progress.

### Validations

- The structure of the submitted flow MUST be compatible with the already-approved flow-definition
  contract (name, steps, edges, joins, geometry) — missing required fields or incompatible types
  MUST be rejected before persistence.
- Acyclicity of the edge set MUST be guaranteed on every mutation.
- Every step's parameters MUST validate against its type's specific schema before the flow can be
  scheduled or dispatched.
- A `custom`-type step with no declared class MUST always fail validation and dispatch.
- A destructive step with no matching typed confirmation MUST block dispatch of the entire flow,
  naming the pending step.
- A WQM category whose values violate the nesting invariant MUST block that category's write.
- A flow save made against a stale revision MUST be refused due to conflict.
- A duplicate flow name (case-insensitive) MUST be refused.

### Key Entities *(include if feature involves data)*

- **Flow**: a named, versioned graph of steps an operator composes; each save increments its
  revision, and a run always pins the revision it was dispatched with.
- **Step**: a node of the flow — a step type plus its configuration; its destructive flag is always
  derived from the type, never editable.
- **Edge**: a directed dependency between two steps; a flow's edge set is always acyclic.
- **Join**: the set of incoming edges of a step with two or more dependencies, plus the
  partial-failure policy in force over it (fixed at `ALL_MUST_SUCCEED` in v1).
- **Run**: an execution of a specific revision of a flow, identified by an identifier generated by
  the platform itself.
- **Step Run**: an execution of a step within a run, with its own state (one of the six closed
  ones), queued/started/finished times, failure reason, and progress.
- **WQM Category**: the Work Queue Manager worker-ceiling configuration that protects the parallel
  execution of steps, subject to the nesting invariant.
- **Step Type (catalog)**: a declared, closed entry — never extensible at runtime — describing
  class, category, destructive flag, and pause capability.
- **Execution resolution record**: the ability to resolve, in a single lookup, an identifier
  observed in the platform's operational records back to the run and step it belongs to.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can persist a newly composed flow and retrieve it with identical
  structure in under 2 seconds.
- **SC-002**: 100% of attempts to introduce a cycle into a flow's graph are rejected at the exact
  moment of the attempt — no saved or validated flow ever contains a cycle.
- **SC-003**: An operator can dispatch a flow and observe, in the dispatch response itself, a
  tracking identifier and a queued time for 100% of the flow's steps.
- **SC-004**: A state change that occurs during a run is observable by a client within 2 seconds,
  for the entire duration of the run.
- **SC-005**: An operator can cancel a step in isolation without any sibling step in the same wave
  being affected, in 100% of attempts.
- **SC-006**: No destructive step ever starts without a matching typed confirmation recorded
  against the operator who provided it.
- **SC-007**: No Work Queue Manager category that violates its nesting invariant is ever accepted,
  and the operator is always told how many other scheduled tasks the change would affect before
  confirming the write.
- **SC-008**: The failure reason reported to the operator for a step that failed is identical, in
  100% of observed cases, to what the platform actually produced.
- **SC-009**: An operator can schedule a validated flow and obtain one native task identifier per
  scheduled step, without any private scheduler of this system ever being triggered.

## Dependencies and Assumptions

- **Already-approved data contracts**: `specs/002-canvas-ui/contracts/openapi.yaml`,
  `specs/002-canvas-ui/contracts/data-model.md`, and
  `specs/002-canvas-ui/contracts/flow-definition.schema.json` are the source of truth for data
  shape and endpoint surface; this spec describes the behavior those contracts require, without
  redefining them.
- **Already-closed compatibility decisions**: `specs/001-validate-async-job-contract/compatibility.md`
  and `decision.md` establish that the platform delegates parallelism to its own asynchronous job
  mechanism, that the access token expires in 60 seconds requiring proactive renewal, and that
  execution identity (GUID) is not exposed by the platform's administrative API for chaining —
  hence this system generates and resolves its own tracking identifiers instead of depending on
  that API for it.
- **`specs/003-backend-objectscript/HANDOFF.md` was not available in the repository at the time this
  spec was written**, despite having been listed as a mandatory source of truth. This spec was
  produced entirely from the four contracts above plus the decisions of
  `001-validate-async-job-contract`, which proved sufficient to cover persistence, validation,
  execution, tracking, control, scheduling, categories, and the catalog with no perceived gaps. If
  `HANDOFF.md` comes to exist with information that contradicts or narrows what is here, this spec
  MUST be revised before planning proceeds.
- An operator authenticates with their own IRIS platform credentials; this system does not manage
  its own user accounts.
- The IRIS instance used to run this backend already has the closed catalog's step types available
  as real platform classes (except `custom`, which will never have its own class supplied by this
  backend).
- A single operator at a time is assumed per run; multi-user concurrency over the same run is not
  an assumption of this spec (consistent with the equivalent exclusion in `002-canvas-ui`).
- The event-publication mechanism accepts both a consumer able to maintain a continuous connection
  and a consumer that only polls periodically — both MUST reflect exactly the same state.

## Open Questions

No blocking question remains: the four attached contracts, plus the decisions already closed in
`001-validate-async-job-contract`, were sufficient to specify complete, testable behavior across
every area of the requested functional scope. The one real gap — the content of `HANDOFF.md`,
referenced but absent from the repository — is recorded as an assumption above, not as an open
question, because it did not prevent producing a complete spec from the rest of the sources.
