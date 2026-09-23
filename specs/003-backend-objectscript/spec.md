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

## Change Log / Post-draft Addendum

### 2026-09-22 — Scheduling scope reduction after implementation validation

Post-implementation validation exposed a behavior gap around scheduled execution of destructive
steps. SC-006 requires typed confirmation before any destructive step starts, but no approved
mechanism exists in v1 for supplying that confirmation at scheduled fire time.

To close that gap explicitly, v1 scheduling scope is reduced as follows:

- any flow containing one or more destructive steps is **out of scope for scheduling**
- `POST /flows/{flowId}/schedule` MUST refuse such a flow with an explicit blocking error
- no native scheduled task MUST be created for such a flow
- destructive steps remain supported for **manual dispatch**, subject to the already-required typed
  confirmation

This is a deliberate product/scope decision, not an implementation detail.

### 2026-09-22 — Operational follow-up after persistence bug validation

Implementation validation also exposed prior persistence defects that could leave historical orphaned
records (for example, entities persisted with broken `flow` references). That does **not** change
the product behavior defined by this spec, but it creates an operational follow-up requirement:

- environments used before the fix may require controlled sanitation of invalid historical data
- sanitation is an operational/migration concern, not a new end-user feature
- before/after evidence of any cleanup should be recorded outside this spec (handoff, runbook, or
  operational note)

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
5. Schedule a validated, non-destructive flow as a native platform task, and manage the Work Queue
   Manager worker ceilings that protect that execution.
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
- Scheduling a validated, non-destructive flow as a native platform task.
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
- Scheduling any flow that contains one or more destructive steps. In v1, such flows must be
  dispatched manually with typed confirmation and are explicitly refused by `/schedule`.

## Actors

- **Operator**: an authenticated user with credentials on the IRIS platform itself, responsible for
  composing, validating, scheduling, dispatching, and tracking flows. This is the only user type
  considered in this spec — there are no roles or permissions differentiated beyond those the
  platform itself already imposes.
- **IRIS Platform**: the system of record for native scheduling, concurrent execution,
