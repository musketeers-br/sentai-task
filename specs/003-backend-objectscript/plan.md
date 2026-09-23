# Implementation Plan: Backend ObjectScript — sentaiTask Orchestration Engine

**Branch**: `003-backend-objectscript` | **Date**: 2026-09-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-backend-objectscript/spec.md`

## ⚠️ About HANDOFF.md

`specs/003-backend-objectscript/HANDOFF.md` **was absent** when the spec was written and **is
present** now. It has been read and fully incorporated into this plan. It confirms the six
already-fixed decisions, adds four technical constraints that were until now implicit (no
unauthenticated web app; no `MatchRoles:"%All"`; no `Xecute` on a request parameter; no
credentials in code — all incorporated into the **Security** section), and explicitly names the
seven points this plan needs to cover (classes/namespaces, persistence, REST, dispatch, SSE,
transaction/concurrency/recovery, tests per layer) — all covered below.

The HANDOFF confirms class names already cited in `002-canvas-ui/spec.md`'s Dependencies
(`sentai.model.*`, `sentai.dispatch.WaveDispatcher`, `sentai.rest.Dispatcher`,
`sentai.model.Category`, `^sentaiRun`) but **does not resolve** two technical gaps that no attached
contract resolves: (1) the exact token-validation mechanism between this dispatcher and the
administrative API, and (2) how edge ordering is preserved in a flow scheduled to run recurrently
(outside the manual dispatch path). Both are recorded as **explicit assumptions** in `research.md`
(R-002, R-007/OQ-1) — not masked — and are the two areas of this plan with the highest risk of
revision if a more detailed HANDOFF appears later, or when the implementation is validated against
a real IRIS instance (the HANDOFF itself already lists this as a known risk).

## Summary

The `003-backend-objectscript` spec requires a backend that persists, validates, dispatches,
executes, and makes trackable an IRIS maintenance flow, fully honoring the contracts already
approved in `002-canvas-ui` (`openapi.yaml`, `data-model.md`, `flow-definition.schema.json`) and
the already-fixed decisions (`ALL_MUST_SUCCEED` join, native scheduling, native GUID, derived
`isDestructive`, single instance, pause restricted to the purge family). The technical approach:
seven `%Persistent` classes under `sentai.model` implement the contract's entities with no change
in shape; a single REST dispatcher (`sentai.rest.Dispatcher`, `%CSP.REST`) exposes exactly the
surface of `openapi.yaml`; `sentai.dispatch.WaveDispatcher` computes wave eligibility from the
persisted graph and delegates actual parallelism to the platform's own `%SYS.WorkQueueMgr`,
dispatching each step through the same asynchronous administrative endpoints already validated in
`001-validate-async-job-contract` — not through the task-creation path that same spec already
proved is unusable for this product's own orchestration (the create→read→GUID cycle does not
close). `sentai.validation.FlowValidator` centralizes every validation rule, reused by
`/validate`, `/schedule`, and `/dispatch`. Execution events are published via SSE reading the same
persisted state the 3-second polling fallback also reads, never a divergent copy.

Post-validation scope adjustment: scheduling is now explicitly limited to non-destructive flows.
Any flow containing a destructive step is refused by `/schedule` with an explicit validation error,
because v1 has no approved mechanism for supplying the typed confirmation required by SC-006 at
scheduled fire time. This is a deliberate scope reduction, not an implementation accident.


## Technical Context

**Language/Version**: ObjectScript (IRIS 2026.2 Community, per `compatibility.md`); no additional
language or runtime — "backend in pure ObjectScript" (HANDOFF).

**Primary Dependencies**: `%CSP.REST` (HTTP routing), `%Persistent` + `%JSON.Adaptor`
(persistence and serialization), `%SYS.WorkQueueMgr` (parallelism delegated to the platform),
`$SYSTEM.Util.CreateGUID()` (identifiers). No external library, no third-party JSON Schema
validation framework — the rules of `flow-definition.schema.json` are implemented directly in
ObjectScript (R-008 in `research.md`).

**Storage**: Native IRIS globals via `%Persistent` classes, in the `IRISAPP_DATA` database already
provisioned by `merge.cpf`; plus one direct global `^sentaiRun` (not a persistent class) for the
execution-resolution registry, in the shape already contracted by
`002-canvas-ui/contracts/data-model.md`.

**Testing**: `%UnitTest`, the same mechanism already referenced in `module.xml` for `dc-sample`,
extended to the `sentai.unittest.*` package (see research.md R-012 and §Tests below).

**Target Platform**: The same IRIS instance already validated in
`001-validate-async-job-contract/compatibility.md` (2026.2, Build 221U), running in the already
provisioned `IRISAPP` namespace.

**Project Type**: Pure backend (no frontend component is touched by this plan — `002-canvas-ui`
remains responsible for the whole presentation territory).

**Performance Goals**: State-change latency observable within 2 seconds (NFR-001); synchronous
dispatch response with all `StepRun`s already created before returning (NFR-002); no other
performance target is in the spec's scope.

**Constraints**: Single instance (NFR-005, no multi-instance coordination); mandatory
authentication on every surface (FR-040, NFR-006); no embedded credential (FR-042); no `Xecute` on
a request parameter (HANDOFF); no `MatchRoles:"%All"` (HANDOFF); no private, in-process scheduler
(FR-031, already-fixed decision); scheduled execution is limited to flows with no destructive steps
(scope reduction decided after implementation validation).


**Scale/Scope**: Seven persistent entities, ~20 REST endpoints (all already in `openapi.yaml`, none
invented here), a closed catalog of seven step types. Scope entirely bounded by `spec.md` — no
capability beyond it is added.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Applies to this slice? | Assessment |
|---|---|---|
| I. Layered Architecture | Yes | `sentai.rest.Dispatcher` (HTTP presentation) never accesses `%Persistent` directly without going through `sentai.validation.FlowValidator`/`sentai.dispatch.WaveDispatcher` (application core); those, in turn, never import anything from `sentai.rest` — the dependency always points from the dispatcher inward. No shortcut crosses the boundary. **Pass.** |
| II. Closed Capability Set | Yes | `sentai.registry.StepType` is a compiled, closed `XData`; no new type can be added via configuration or operator input; no `Xecute` over a request parameter exists in any class of this plan (an explicit HANDOFF constraint, verifiable by code review). **Pass.** |
| III. Delegated Authorization | Yes | `sentai.rest.Dispatcher.OnPreDispatch` validates the token on every request, with no cache across requests (FR-041); every privileged action (dispatch, destructive confirmation, run control) is authorized by the platform at the moment it occurs, never inferred from an earlier authorization. **Pass.** |
| IV. Errors as Values | Yes | `ValidationReport` (errors/warnings) and `StepRun.failureReason` are explicit values that cross the REST boundary as data, never as an unhandled exception; the two transactional boundaries (R-011) guarantee a partial failure is never reported as success. **Pass.** |
| V. Verifiable Increments | Yes — organizes the §Recommended implementation sequence below | Every phase of the plan delivers something an automated test (or the quickstart) can observe end to end — never "the model layer for X" in isolation. **Pass.** |
| VI. Technology Agnosticism | Yes | ObjectScript, `%CSP.REST`, `%Persistent`, `%SYS.WorkQueueMgr` are Plan-level choices, justified in `research.md` against the principles above; none of it is in the Constitution. **Pass.** |

No violation to justify. **Complexity Tracking is empty.**

## Technical Vision

The backend is a single ObjectScript module (`sentai`) compiled inside the same `IRISAPP`
namespace the development template already provisions — not a separate service, not a second
process. It splits into five responsibilities that never mix in the same class (an explicit
HANDOFF request): **persistence** (`sentai.model.*`, pure data with invariants), **validation**
(`sentai.validation.FlowValidator`, pure rules over that data), **dispatch**
(`sentai.dispatch.WaveDispatcher`, the only class that talks to `%SYS.WorkQueueMgr` and to the
administrative API's asynchronous endpoints), **API** (`sentai.rest.Dispatcher`, HTTP↔service-call
translation, nothing else), and **events** (the same dispatcher's SSE method, reading state that
dispatch already persisted — never a parallel state channel).

None of these five parts duplicates what the IRIS platform already does: scheduling is always
native (`%SYS.Task.Definition`), parallelism is always `%SYS.WorkQueueMgr`, identifiers are always
`$SYSTEM.Util.CreateGUID()`, authorization is always delegated to the platform itself. What this
backend actually builds is the thin layer that was missing between "the operator composed a graph
on the canvas" and "the platform executes that graph respecting its dependencies" — exactly what
`spec.md §Context and Problem` describes as the gap the canvas alone does not close.

## Architecture

```
                        ┌─────────────────────────┐
   HTTP (Bearer token)  │  sentai.rest.Dispatcher  │   (%CSP.REST — /csp/sentai/api/v1)
  ───────────────────►  │  OnPreDispatch: auth     │
                        │  UrlMap: 1:1 with openapi│
                        └─────────┬────────────────┘
                                  │ delegates, never accesses Model directly
              ┌───────────────────┼───────────────────┬─────────────────────┐
              ▼                   ▼                   ▼                     ▼
  sentai.validation      sentai.dispatch      sentai.wqm            sentai.catalog
  .FlowValidator         .WaveDispatcher      .CategoryService      .TaskService
              │                   │                   │                     │
              │                   │  JOB (background)  │  passthrough        │  read
              │                   ▼                   ▼                     ▼
              │        %SYS.WorkQueueMgr    Administrative API (validated in 001)
              │                   │
              ▼                   ▼
      sentai.model.*  ◄───────────┘  (Flow/Step/Edge/Join/Run/StepRun/Category/LogEntry)
              │
              ▼
        ^sentaiRun (resolution global — written in the dispatch transaction)

  sentai.registry.StepType — compiled XData, queried by Validator, WaveDispatcher, and REST
```

The dependency arrow always points inward (`sentai.model`); `sentai.rest.Dispatcher` sits at the
edge and is the only point that speaks HTTP. `sentai.dispatch.WaveDispatcher` is the only point
that talks to `%SYS.WorkQueueMgr` and to the administrative API — no other class makes a direct
execution call, which keeps Constitution I (Layered Architecture) verifiable by inspection.

## Components

| Component | Type | Single responsibility |
|---|---|---|
| `sentai.rest.Dispatcher` | `%CSP.REST` | Routing, authentication, JSON (de)serialization, error-to-HTTP-status translation |
| `sentai.model.Flow` | `%Persistent` | A flow's identity and revision |
| `sentai.model.Step` | `%Persistent` | A node of the flow; derives `isDestructive` from the registry, never accepts it as input |
| `sentai.model.Edge` | `%Persistent` | A directed dependency; participates in the cycle check |
| `sentai.model.Join` | `%Persistent` | The partial-failure policy of a step with ≥2 inputs |
| `sentai.model.Run` | `%Persistent` | An execution; carries `eventVersion` for SSE |
| `sentai.model.StepRun` | `%Persistent` | An execution of a step; the sole owner of state transitions |
| `sentai.model.Category` | `%Persistent` | Local mirror of a WQM category (see §Data and Persistence) |
| `sentai.model.LogEntry` | `%Persistent` | One line of a run's log |
| `sentai.validation.FlowValidator` | Service | Every validation rule, reused across three endpoints |
| `sentai.dispatch.WaveDispatcher` | Service + background job | Eligibility, enqueueing, transitions, control |
| `sentai.registry.StepType` | Compiled `XData` | Closed catalog of types |
| `sentai.wqm.CategoryService` | Service | Passthrough + invariant + `affectedTaskCount` |
| `sentai.catalog.TaskService` | Service (P3, reducible) | Reading the instance's task catalog |

## Data and Persistence

Detailed in [`data-model.md`](data-model.md) (Phase 1). Summary of the decisions that matter most
for whoever decomposes this into tasks:

- Seven `%Persistent` + `%JSON.Adaptor` classes, one per entity from the `002-canvas-ui` contract,
  with no field added beyond `Run.eventVersion` (internal, never serialized) and the new
  `LogEntry` class (which only materializes what `openapi.yaml`'s `RunDetail.log` already
  anticipated).
- `Step.parameters` is an embedded `%DynamicObject` — not its own table — exactly as
  `data-model.md` (002) already specifies.
- `Flow.canvasGeometry` is stored as an opaque stream; no validation or dispatch class reads it
  (FR-009), which is verifiable by reviewing those classes' imports.
- `sentai.model.Category` is a **local mirror**, not the source of truth — the source of truth for
  worker ceilings is the platform itself (`/api/admin/v2/wqm-categories`, validated in
  `compatibility.md` Q5). The mirror exists only so `sentai.wqm.CategoryService` can compute
  `affectedTaskCount` (how many tasks *of this product* use the category) without an expensive
  cross-query on every read; every write is always an immediate passthrough to the administrative
  API, never a local write that diverges from the platform.
- Execution identifiers (`Run.guid`, `StepRun.guid`) use `$SYSTEM.Util.CreateGUID()`;
  `^sentaiRun` is written inside the same dispatch transaction — never afterward.

## APIs and Contracts

`sentai.rest.Dispatcher` implements exactly the surface of
[`002-canvas-ui/contracts/openapi.yaml`](../002-canvas-ui/contracts/openapi.yaml) — no new
endpoint, no new request/response field. The endpoint→class mapping is in
[`contracts/rest-mapping.md`](contracts/rest-mapping.md); the shape of SSE events (which the
OpenAPI deliberately leaves as a generic `type: string`) is in
[`contracts/sse-protocol.md`](contracts/sse-protocol.md).

Authentication: every route requires the same 60-second access/refresh token pair the
administrative API already uses (`002-canvas-ui` Clarification), validated in `OnPreDispatch` —
see `research.md` R-002 for the decision and the open risk around the exact validation mechanism.

## Execution and Dispatch

`sentai.dispatch.WaveDispatcher` is the only class that decides "what runs now": it reads the
persisted edge graph, computes which steps have every source in a terminal state satisfying the
join policy, and enqueues each one as a unit of work in `%SYS.WorkQueueMgr` under the step's WQM
category — actual parallelism (including respecting worker ceilings) is entirely
`%SYS.WorkQueueMgr`'s, never this code's (FR-020).

To actually execute a step, `WaveDispatcher` calls the same asynchronous administrative-API
endpoint already proven functional in `001-validate-async-job-contract` (HTTP 202 + `Location` for
`async-result`; pause/resume/cancel confirmed HTTP 200) — not the task-creation path
(`POST /v2/task`), which that same spec already proved does not close the create→read→GUID cycle
for this product's own orchestration. That choice is detailed and justified in `research.md`
R-005.

Dispatch (`/dispatch`) is synchronous only up to the creation of `Run`+`StepRun`s (one
transaction, see §Transaction below); `WaveDispatcher` then continues as a background IRIS job —
the HTTP 202 response does not wait for any step to finish.

Scheduling (`/schedule`) is a **different** path: it compiles a validated, non-destructive flow into
native `%SYS.Task` entries. As a post-validation scope reduction, any flow containing at least one
destructive step is rejected by `/schedule` before task creation. This avoids inventing an implicit
or hidden mechanism for satisfying SC-006's typed confirmation requirement during a future scheduled
execution. In v1, destructive steps are dispatchable manually with confirmation, but not schedulable.

## Validation

`sentai.validation.FlowValidator` is the only class that produces a `ValidationReport`. It is
called from three points — `/validate` (explicit use), `/schedule`, and `/dispatch` (as a blocking
precondition, FR-018/FR-032) — always with the same code, never a duplicated copy of the rule per
endpoint. It checks, in this order: structure against `flow-definition.schema.json` (required
fields, types), graph acyclicity, per-step-type parameter schema, namespace existence, the WQM
category invariant, and — as a warning, never an error — the single, fixed database-directory
mount precondition check. A `custom` step with no `customClass` is always an error, never a
warning (FR-011).

## Events/SSE

`GET /runs/{runGuid}/events`, implemented in `sentai.rest.Dispatcher` itself, keeps the HTTP
connection open and writes events as `Run.eventVersion` advances — never from a separate in-memory
state copy from what `GET /runs/{runGuid}` also reads, guaranteeing the 3s polling fallback never
diverges from what the stream would have delivered. The exact event shape, latency guarantees, and
termination conditions: [`contracts/sse-protocol.md`](contracts/sse-protocol.md). The biggest
technical risk here — whether IRIS's private web server sustains an open connection for the entire
duration of a run — is flagged in `research.md` (risk #3) and is the same risk the HANDOFF had
already named.

## Error model and failure propagation

Every predictable failure crosses the REST boundary as a value (`ValidationReport`, `Problem`, or a
specific HTTP status already contracted in `openapi.yaml`) — never as an unhandled ObjectScript
exception leaking to the client (Constitution IV). `sentai.rest.Dispatcher` is the only point that
translates a service condition into an HTTP status; the full table is in
[`contracts/rest-mapping.md §Errors`](contracts/rest-mapping.md). `StepRun.failureReason` is
propagated byte for byte from what the call to the administrative API returned — no intermediate
layer summarizes, rewords, or truncates that string (FR-023), which is verifiable by ensuring no
class between `WaveDispatcher` and `StepRun.TransitionTo` touches that field beyond copying it.

## Transaction, consistency, and concurrency

Two explicit `TSTART`/`TCOMMIT` boundaries (detailed in `research.md` R-011): flow save (the whole
graph + revision, one unit) and dispatch (`Run` + all `StepRun`s + `^sentaiRun`, one unit).
Concurrency between operators editing the same flow is resolved by optimistic locking via
`revision` — no long-lived pessimistic lock, consistent with "single instance" and with the main
path being one operator at a time. Recovery: since `WaveDispatcher` runs as a background IRIS job
after the dispatch transaction commits, a `Run` whose job died (for example, an instance restart)
ends up with steps stuck in `queued`/`running` with no progress — this plan does not automatically
resolve that recovery (there is no spec requirement for it); it is recorded here as a known
operational gap, not masked, for a future decision if it ever matters.

## Security

The `/csp/sentai/api/v1` CSP application is configured without "Unauthenticated" and without
`MatchRoles:"%All"` (explicit HANDOFF constraints) — a dedicated role (`%sentai_Operator`,
proposed) is required. `OnPreDispatch` validates the same 60-second token the administrative API
uses, with no cache across requests (FR-041, Constitution III). No request parameter is passed to
`Xecute`, `$system.Process`, or any form of dynamic execution in any class of this plan — every
input is always data, never code (Constitution II, an explicit HANDOFF constraint). No credential
is read from source code or any versioned file — only from the already-authenticated IRIS session
context (FR-042).

## Minimal observability

`sentai.model.LogEntry` records, per run, every relevant event (state change, destructive
confirmation received, pause/cancel requested) with a timestamp and severity — the same shape
`RunDetail.log` already exposes via REST, not a parallel logging mechanism.
`^sentaiRun("idx", ...)` allows resolving, in a single query, an identifier seen in the platform's
own operational records (`messages.log`) back to the run/step (FR-043) — the main diagnostic tool
when something fails on the platform side, not this backend's. No additional telemetry, metric, or
dashboard is in this spec's scope.

## Technical risks, trade-offs, and assumptions

Consolidated in [`research.md` §Technical risks and trade-offs](research.md); the two with the
highest risk of revision if `HANDOFF.md` is later expanded or a real instance is used for
validation:

1. **Token-validation mechanism between dispatchers** (research.md R-002) — assumed reusable; a
   fallback is documented (an internal call to `GET /api/admin/info`) if it is not.
2. **Dependency ordering for recurring scheduled runs of non-destructive flows** (research.md
   R-007/OQ-1) — still the biggest remaining scheduling risk, but now narrowed because destructive
   flows are explicitly excluded from `/schedule` in v1.


The remaining risks (SSE connection duration; a 1:1 mapping of each step type to an asynchronous
administrative endpoint equivalent to the one already validated) are in the same table, with
mitigation, and do not block planning.

## Tests per layer

`%UnitTest`, extending the mechanism `dc-sample` already uses (see `research.md` R-012):

| Layer | Test package | What it verifies |
|---|---|---|
| Persistence/invariants | `sentai.unittest.model` | Name uniqueness, `isDestructive` never writable as input, illegal `StepRun` transitions rejected |
| Validation | `sentai.unittest.validation` | Each `FlowValidator` rule in isolation (cycle, per-type schema, namespace, WQM invariant, precondition) |
| Dispatch | `sentai.unittest.dispatch` | Wave eligibility, `StepRun` transitions, join failure propagating to the target — with the call to the administrative API replaced by a test double |
| REST | `sentai.unittest.rest` | Status code and payload shape of every endpoint against `openapi.yaml`; 401 with no token; 409/422/428 in the contracted scenarios |
| Registry | `sentai.unittest.registry` | The seven types exist with the correct category/destructive-flag/pausability |

Runnable via `zpm "test sentai-task -v -only"` — the same command, no new infrastructure.

## Assumptions, Open Questions, and Technical Done Criteria

### Assumptions

The following assumptions are used by this plan and MUST NOT be treated as permanently settled architecture until validated during implementation:

- **A-01 — Token validation bridge is available or can be safely emulated.**  
  `sentai.rest.Dispatcher` is assumed to be able to validate the same short-lived bearer token used by the administrative API, either through a native IRIS mechanism or through the documented fallback of an internal authenticated call.

- **A-02 — Administrative async endpoints exist for all supported step types with behavior compatible with the validated pattern from spec 001.**  
  The plan assumes that each supported maintenance operation can be started, observed, and controlled through an async administrative endpoint with semantics compatible with the already validated integrity-check flow.

- **A-03 — SSE is viable in the target IRIS deployment model.**  
  The plan assumes that a long-lived HTTP response can remain open for the duration needed to stream run events with the latency required by the spec.

- **A-04 — Scheduled non-destructive flows can preserve dependency ordering by delegating actual orchestration back to the backend dispatch path.**  
  The current baseline assumes that native scheduling can trigger the backend orchestration entrypoint rather than independently reproducing dependency logic in each scheduled task. This assumption applies only to non-destructive flows, since destructive flows are explicitly out of scheduling scope in v1.

- **A-05 — Local category mirroring is acceptable as a read-optimization and impact-calculation aid.**  
  The plan assumes that keeping a local mirror of category metadata does not create unacceptable drift as long as the platform remains the source of truth and all writes remain passthrough.

### Open Questions

The following questions remain open and should be tracked explicitly through implementation rather than silently absorbed into code:

- **OQ-01 — What is the exact supported mechanism for validating administrative bearer tokens inside `sentai.rest.Dispatcher`?**
- **OQ-02 — For each non-validated step type, which administrative async endpoint is the exact execution target, and does it preserve the same lifecycle semantics required by the plan?**
- **OQ-03 — What is the supported and production-safe strategy for preserving dependency ordering in recurring scheduled runs for non-destructive flows?**
- **OQ-04 — What timeout, buffering, and connection-lifetime limits apply to SSE in the target IRIS web server configuration?**
- **OQ-05 — Under restart or worker interruption, what operational recovery path is required for runs left in non-terminal states?**

### Technical Done Criteria

The implementation MUST NOT be considered technically complete until the following conditions are demonstrated:

- **TD-01 — Authentication is validated against a real target IRIS environment.**  
  Either the native token-validation mechanism or the documented fallback path must be proven to work end-to-end.

- **TD-02 — Each supported step type is validated against its actual execution path.**  
  The implementation must prove that every supported step type can be started and observed through its mapped execution mechanism.

- **TD-03 — SSE behavior is validated in the target environment.**  
  The implementation must demonstrate that event streaming remains usable under expected run duration and connection behavior, or explicitly downgrade to the polling-only path if SSE is not operationally viable.

- **TD-04 — Scheduled execution ordering is demonstrated or explicitly reduced in scope.**  
  The implementation must prove that scheduled flows preserve dependency semantics, or else the scheduling scope must be narrowed and reflected back into the spec and plan.

- **TD-05 — No assumption above remains implicit in code or docs.**  
  Any assumption that survives into implementation must be either validated, converted into an explicit product limitation, or escalated as a change request.

- **TD-06 — Scheduling refusal for destructive flows is enforced and observable.**  
  The implementation must demonstrate that any flow containing at least one destructive step is refused by `/schedule` with an explicit blocking error, and that no native `%SYS.Task` entry is created in that scenario.

## Requirements-to-technical-components mapping

See [`data-model.md` §Requirements → entities/classes mapping`](data-model.md) for the full
FR-001…FR-043 → class table. Summary by the spec's priority:

| Spec priority | Requirements | Main components |
|---|---|---|
| P0 — Persistence and composition | FR-001–011 | `sentai.model.*`, `sentai.registry.StepType` |
| P0 — Validation | FR-012–015 | `sentai.validation.FlowValidator` |
| P1 — Dispatch and execution | FR-016–024 | `sentai.model.Run/StepRun`, `sentai.dispatch.WaveDispatcher`, `^sentaiRun` |
| P1 — Tracking and control | FR-025–030 | `sentai.dispatch.WaveDispatcher`, SSE in `sentai.rest.Dispatcher` |
| P2 — Scheduling and categories | FR-031–036 | `sentai.wqm.CategoryService`, native administrative API |
| P3 — Catalog (reducible) | FR-037–039 | `sentai.registry.StepType`, `sentai.catalog.TaskService` |
| Cross-cutting | FR-040–043 | `sentai.rest.Dispatcher.OnPreDispatch`, `^sentaiRun` |

## Recommended implementation sequence

Designed so `/speckit-tasks` can decompose this into small, testable units (an explicit HANDOFF
request), each phase delivering something verifiable before the next one starts:

1. **Persistence foundations** — the seven `sentai.model.*` classes plus
   `sentai.registry.StepType` (`XData`), with no API yet. Testable via plain `%UnitTest` (P0).
2. **Structural validation** — `sentai.validation.FlowValidator` covering acyclicity, per-type
   schema, and the always-blocks-`custom` rule. Still no REST API — directly testable (P0).
3. **Composition API** — `sentai.rest.Dispatcher` covering only `/flows*` and
   `/flows/{id}/validate`, with authentication already mandatory from the very first exposed
   endpoint (never a "temporarily unauthenticated" phase). Closes P0 end to end — quickstart.md
   steps 1–4 already pass here.
4. **Dispatch and state transition** — `sentai.model.Run/StepRun` complete with the state machine,
   the dispatch transaction, `^sentaiRun`, and the `/dispatch` endpoint — still without real
   parallelism (a single step at a time, sequentially, as scaffolding). Proves the synchronous
   shape (FR-016).
5. **Dispatch with real parallelism** — the complete `sentai.dispatch.WaveDispatcher`: wave
   eligibility, `%SYS.WorkQueueMgr`, integration with the asynchronous administrative endpoint per
   step type, join policy. Closes execution P1 — quickstart.md step 6 passes here.
6. **Control and tracking** — `/cancel`, `/pause`, `/rerun` (run and step), plus the SSE endpoint.
   Closes P1 completely — quickstart.md step 7 passes here.
7. **WQM categories** — `sentai.wqm.CategoryService`, passthrough plus invariant plus
   `affectedTaskCount`. Closes half of P2 — quickstart.md step 8 passes here.
8. **Scheduling** — `/schedule`, resolving (or explicitly deferring with a risk note) the OQ-1
   assumption before declaring this step complete. Closes P2 — quickstart.md step 9 passes here.
9. **Catalog** — `sentai.catalog.TaskService` and the three `/catalog/tasks*` endpoints. P3,
   explicitly the first phase to cut if time does not allow it (the spec itself already marks
   this).
10. **Operational sanitation and real-environment verification** — execute the controlled cleanup of
    orphaned persistence artifacts from pre-fix builds, record before/after evidence, and rerun the
    relevant quickstart and scheduling checks on a clean environment.

Each phase 3–9 adds REST endpoints on top of an already-authenticated, already-tested base — no
phase depends on "unlocking" authentication or tests later; both exist starting in phase 3.

## Data sanitation after persistence bug fixes

Implementation validation revealed that earlier versions of the backend persisted orphaned records
with `flow = 0` due to assigning raw ids directly to reference properties. These invalid records can
remain in the instance even after the code is fixed and must not be ignored operationally.

Required sanitation procedure:
1. record pre-cleanup counts of orphaned records by class (`Step`, `Edge`, and any related entity
   found to carry `flow = 0` or equivalent invalid references)
2. record sample evidence of affected ids before deletion or repair
3. execute cleanup through a reviewable procedure, preferably a dedicated sanitation script checked
   into the repository or attached to the operational handoff
4. record post-cleanup counts proving the environment is clean
5. preserve a short audit note describing what was removed, when, and by whom

This sanitation activity is operational follow-up to the bug fix, not a substitute for the fix
itself.

## Project Structure

### Documentation (this feature)

```text
specs/003-backend-objectscript/
├── plan.md                    # This file
├── research.md                # Phase 0 output — technical decisions + risks
├── data-model.md              # Phase 1 output — classes, indexes, requirements mapping
├── quickstart.md              # Phase 1 output — build/test/verify end to end
├── contracts/
│   ├── rest-mapping.md        # Phase 1 output — endpoint → class/method → requirement
│   └── sse-protocol.md        # Phase 1 output — event shape (not defined in openapi.yaml)
├── checklists/requirements.md # Pre-existing (from the spec)
└── HANDOFF.md                 # Pre-existing — incorporated technical source
```

### Source Code (repository root)

```text
src/
├── sentai/
│   ├── rest/
│   │   └── Dispatcher.cls               # %CSP.REST — sole HTTP entry point
│   ├── model/
│   │   ├── Flow.cls
│   │   ├── Step.cls
│   │   ├── Edge.cls
│   │   ├── Join.cls
│   │   ├── Run.cls
│   │   ├── StepRun.cls
│   │   ├── Category.cls
│   │   └── LogEntry.cls
│   ├── validation/
│   │   └── FlowValidator.cls
│   ├── dispatch/
│   │   └── WaveDispatcher.cls
│   ├── registry/
│   │   └── StepType.cls                 # XData — closed catalog
│   ├── wqm/
│   │   └── CategoryService.cls
│   └── catalog/
│       └── TaskService.cls              # P3, reducible
├── dc/sample/                            # UNCHANGED — pre-existing, not touched
tests/
└── sentai/
    └── unittest/
        ├── model/
        ├── validation/
        ├── dispatch/
        ├── rest/
        └── registry/

module.xml                     # MODIFIED: adds Resource "sentai.PKG" and UnitTest package sentai.unittest
merge.cpf                      # UNCHANGED: IRISAPP namespace/database already provisioned
Dockerfile, docker-compose.yml # UNCHANGED: no new infrastructure (out of scope for this spec)
```

**Structure Decision**: Pure backend inside the repository's already-existing ObjectScript structure
(`src/<package>/Class.cls`, per `module.xml`/`dc-sample`) — no new top-level folder, no new build
mechanism. `frontend/` (if it already exists from `002-canvas-ui`) is not touched by this plan.

## Complexity Tracking

No Constitution Check violation to justify. This section remains intentionally empty.
