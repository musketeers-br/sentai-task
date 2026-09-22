# Phase 0 — Research

Feature: `003-backend-objectscript` · Date: 2026-09-22

`HANDOFF.md` is present at this point (it was not when the spec was written) and has been
incorporated as a technical source. It fixes: pure ObjectScript, no unauthenticated web app, no
`MatchRoles:"%All"`, no `Xecute` on a request parameter, no credentials in code, `failureReason`
verbatim, and it explicitly asks that the plan decompose persistence, validation, dispatch, API,
and events as separate responsibilities. Every decision below honors those constraints.

---

## R-001 — REST framework and entry point

**Decision**: A single dispatcher, `sentai.rest.Dispatcher`, subclass of `%CSP.REST`, with an
`XData UrlMap` mirroring 1:1 the paths of `openapi.yaml` (`/flows`, `/flows/:flowId`, ...), mounted
as a CSP application at `/csp/sentai/api/v1` (the contract's own `servers.url`). Each `UrlMap`
method immediately delegates to an application-layer service class — the dispatcher itself
contains no business logic, only routing, JSON parsing/serialization, and HTTP error handling.

**Rationale**: `openapi.yaml` already states, in its own description, "Served by an ObjectScript
%CSP.REST dispatcher under the sentai package" — this class name is already an approved contract
(also cited in `002-canvas-ui/spec.md`'s Dependencies), not a new choice made by this plan.

**Alternatives considered**: Interoperability (`Ens.BusinessService` with a REST adapter) —
rejected because it adds the IRIS Interoperability production infrastructure, which the HANDOFF
does not ask for ("backend in pure ObjectScript") and which Constitution VI would treat as an
unjustified technology dependency for what is, fundamentally, an HTTP router.

## R-002 — Authentication and authorization

**Decision**: The `/csp/sentai/api/v1` CSP application is configured with mandatory
authentication (`AutheEnabled` without the "Unauthenticated" option) and without
`MatchRoles:"%All"` — access requires a dedicated role (proposed: `%sentai_Operator`) granted to
the operator on the platform itself. The dispatcher implements `OnPreDispatch` to validate the
same 60-second access/refresh token pair the administrative API already uses
(`002-canvas-ui` Clarifications: "the same 60-second JWT login/refresh mechanism is used for every
call, both SysAdmin and `sentai.rest.Dispatcher`"), rejecting with 401 any request without a valid,
unexpired token — never caching or inferring this decision across requests (Constitution III,
FR-041).

**Rationale**: `compatibility.md` (spec 001) documents the observable behavior of the
administrative API's login/refresh, but does not document the internal mechanism by which the
platform itself validates that token — that is internal to IRIS. Reusing the same token pair
(rather than inventing a second authentication form) is the only reading compatible with the
already-approved Clarification.

**Open risk (explicitly flagged, not masked)**: the exact way to validate, inside
`sentai.rest.Dispatcher`, a token issued by the administrative endpoint (`/api/admin/login`) MUST
be confirmed against a real IRIS instance before implementation — HANDOFF already lists this as a
known risk ("SSE and asynchronous dispatch require technical validation on the target IRIS
instance"); the same applies to cross-API token validation. This plan assumes the platform exposes
a usable form of token validation inside the IRIS process (for example, via a system class the
administrative API itself already uses); if that form does not exist, the alternative is for the
dispatcher to internally call `GET /api/admin/info` with the same Bearer token received, treating a
200 response as proof of validity — functionally correct, but with the cost of an extra HTTP call
per request, to be confirmed as acceptable or replaced during implementation.

## R-003 — Entity persistence

**Decision**: One `%Persistent` class per entity from the already-approved `data-model.md`, all
under the `sentai.model` package, in the `IRISAPP` namespace already provisioned by
`merge.cpf`/`iris.script` (no new namespace or database is created): `sentai.model.Flow`, `.Step`,
`.Edge`, `.Join`, `.Run`, `.StepRun`, `.Category`. Each class uses `%JSON.Adaptor` for
(de)serialization compatible with the schemas of `openapi.yaml`/`flow-definition.schema.json`.
`Step.parameters` uses `%DynamicObject` (embedded, not its own class), as already specified in
`data-model.md`. `Flow.canvasGeometry` uses `%Stream.GlobalCharacter`, stored but never read by
`sentai.dispatch.WaveDispatcher` or `sentai.validation.FlowValidator` (FR-009).

**Rationale**: `data-model.md` already names these seven classes and their fields; this plan does
not reopen them, it only picks the standard IRIS persistence mechanism (`%Persistent`) that
implements them without inventing an ORM or an additional data-access layer (YAGNI).

**Alternatives considered**: A single `Flow` class serializing steps/edges/joins as a raw-JSON
`%Stream` property — rejected because it prevents indexing and direct queries (for example, "every
edge whose target is X"), which are needed for cycle detection and wave eligibility, without
deserializing the whole flow on every check.

## R-004 — Execution identifiers (GUID)

**Decision**: `$SYSTEM.Util.CreateGUID()` for `Run.guid` and `StepRun.guid`, exactly as
`data-model.md` already specifies. The `^sentaiRun` global is written inside the same dispatch
transaction, in the shape already contracted:

```
^sentaiRun(runGuid)              = $lb(flowId, flowRevision, startedAt, dispatchedBy)
^sentaiRun(runGuid, stepId)      = stepRunGuid
^sentaiRun("idx", stepRunGuid)   = $lb(runGuid, stepId)
```

**Rationale**: Already a fixed decision (not reopened); `data-model.md` already defines the exact
shape of the global. Implementing it as a direct global (not a persistent class) preserves the
documented purpose — O(1) fast resolution of an identifier seen in `messages.log` back to a
run/step (FR-043) — without the overhead of a SQL index for an access pattern that is always by
exact key.

## R-005 — Execution and parallelism

**Decision**: `sentai.dispatch.WaveDispatcher` (a name already cited in `002-canvas-ui/spec.md`'s
Dependencies) is responsible for: (a) computing, from the persisted edge graph, which steps are
eligible at any given moment (every source of their incoming edges in a terminal state, satisfying
the join policy); (b) enqueueing each eligible step as a unit of work in `%SYS.WorkQueueMgr`, under
the step's WQM category (`wqmCategory`), delegating actual parallelism — including respecting the
worker ceilings — to the platform's own mechanism (FR-020, decision.md "delegate parallel
execution to the platform"); (c) for each step, starting the underlying operation through **the
same asynchronous administrative-API endpoint already validated in `compatibility.md`** (for
example, `POST /api/admin/v2/database-dir/integrity-check` for `integrity-check`), obtaining the
`async-result` `Location` and using the polling/pause/resume/cancel already confirmed functional in
spec 001 (Q3/Q4) to track and control that operation; (d) mapping the observed state of that
asynchronous job onto `StepRun`'s six closed states; (e) upon a step's completion, recomputing
eligibility and enqueueing the next wave.

`WaveDispatcher` is started as a background IRIS job (`JOB` command) right after the synchronous
dispatch transaction (R-004/R-010) commits — the HTTP 202 response to
`POST /flows/{flowId}/dispatch` does not wait for `WaveDispatcher` to finish any wave.

**Rationale**: Reuses behavior already validated with real evidence (spec 001 Q3/Q4: HTTP 202 +
`Location`, Running→Finished transitions, pause/resume/cancel all HTTP 200) instead of depending
on the path spec 001 itself already proved does not work for this product's own orchestration —
task creation via `POST /v2/task`, whose create→read→GUID cycle does not close (Q6).
`WaveDispatcher`, therefore, never creates a native task for immediate dispatch; native tasks
(`%SYS.Task.Definition`) exist only for the **scheduling** path (R-007), which is a different
contract.

**Alternatives considered**: Implementing parallelism with this product's own IRIS processes
(`JOB` per step, without `%SYS.WorkQueueMgr`) — rejected because it would not natively respect
per-category WQM worker ceilings (FR-033–036), forcing this system to reimplement its own worker
counting — exactly the private execution engine FR-020 prohibits.

## R-006 — Ordering by dependencies and join policy

**Decision**: Eligibility is a pure function over persisted state: a step enters the next wave when,
for every incoming edge, the source step is in one of the terminal states (`completed`, `failed`,
`cancelled`) and the target's join policy (always `ALL_MUST_SUCCEED` in v1) is either satisfied or
definitively violated. When any required input fails, `WaveDispatcher` transitions the target step
directly to `failed` (never enqueueing it into `%SYS.WorkQueueMgr`), with `failureReason` naming
the input that failed (FR-021) — no new state is ever evaluated.

**Rationale**: `data-model.md` already defines `Join` as the set of incoming edges plus the policy;
computing eligibility from the persisted graph, without consulting `Flow.canvasGeometry`, is
exactly what FR-009 and FR-019 require.

## R-007 — Native scheduling vs. immediate dispatch

**Decision**: `POST /flows/{flowId}/schedule` compiles each step of the flow into its own
`%SYS.Task.Definition` entry (via the same administrative API already validated in
`compatibility.md` Q1/Q2, accepting the 31 properties the platform requires and not relying on any
identifier returned by that call — the `taskIds` returned to the operator are built from the `Id`
obtained by a subsequent listing, not from the creation response body, which spec 001 already
proved comes back with no identifier).

**Rationale / Open Question (OQ-1, explicitly recorded)**: neither `openapi.yaml` nor
`data-model.md` specifies how ordering by edges/joins is preserved when a scheduled flow fires in a
**recurring, native** way (outside the manual `/dispatch` path), given that spec 001 already
proved that native chaining via `RunAfterGUID` does not close the create→read→GUID cycle for
tasks created by this product (Q6). **Assumption adopted by this plan**: each native task created
by `schedule` calls back into this same backend on its `OnTask()` (equivalent to dispatching the
flow) — that is, only the steps with no incoming edges receive a native task that actually starts a
run; native tasks for subsequent steps exist to satisfy FR-031 ("one task identifier per scheduled
step"), but their real execution is suppressed by `WaveDispatcher`, which will already have carried
that step to its terminal state via the earlier wave. This is the area of this plan with the
highest risk of revision if the real `HANDOFF.md` ends up detailing something different — no spec
or attached contract resolves this unambiguously.

## R-008 — Validation (structural and precondition)

**Decision**: `sentai.validation.FlowValidator`, a (non-persistent) service class with a
`Validate(flowId) As %DynamicObject` method that returns the `ValidationReport` shape from
`openapi.yaml` (`errors[]`, `warnings[]`). Implements, in pure ObjectScript — without an external
JSON Schema library — the rules already enumerated in `data-model.md §Validation rules` and in the
spec: acyclicity (reuses the same algorithm as `R-006`/FR-007), per-type parameter schema (read
from the type registry, `R-009`), namespace existence (queries `%SYS.Namespace` or the equivalent
on the active instance), the WQM category invariant (delegated to a check shared with `R-011`), and
the single, fixed precondition check for database-directory mount status (reading the
read-only state of the referenced database directory, via an IRIS system API — not a general
engine).

**Rationale**: Keeps validation as an isolated, reusable responsibility for both the explicit
`/validate` action and the mandatory structural checks in `/schedule` and `/dispatch` (FR-018,
FR-032), without duplicating the rules in three places.

## R-009 — Step-type catalog (closed registry)

**Decision**: `sentai.registry.StepType`, a class with an `XData` block (static, compiled JSON)
enumerating the seven types already defined in `data-model.md §Step types`: target class, category,
destructive flag, and pause capability. No value comes from runtime configuration or operator
input — it is closed data, compiled together with the class (Constitution II).
`Step.isDestructive` is always computed by looking up this registry by the step's `type`; never
persisted as a direct operator input even if present in the payload (FR-010).

**Rationale**: `data-model.md` already describes the full table; a compiled `XData` is the most
direct form of "data, not code branch" that the contract itself asks for, without introducing a
plugin or dynamic-loading mechanism that Constitution II would prohibit.

## R-010 — Execution events (SSE) and polling fallback

**Decision**: `GET /runs/{runGuid}/events` is implemented in `sentai.rest.Dispatcher` itself as a
method that takes over the HTTP response, sets `Content-Type: text/event-stream`, and enters a
loop that: reads an incremental version counter kept on `sentai.model.Run` (bumped on every state
change of any `StepRun` of the run or a new `LogEntry`), writes the events new since the last sent
counter as `data: {...}\n\n`, calls `Do %response.Flush()`, and sleeps a short interval (proposed:
500ms) before checking again — guaranteeing delivery within 2 seconds (NFR-001) with margin. The
loop ends when the run reaches a terminal state (emits a final event) or when
`%response.IsClientConnected()` returns false. See `contracts/sse-protocol.md` for the exact event
shape.

`GET /runs/{runGuid}` (the 3s polling fallback `openapi.yaml` already documents) reads the same
persisted state — never a divergent in-memory copy — ensuring the client that cannot maintain SSE
sees exactly the same state it would have received by event.

**Rationale**: `openapi.yaml` already declares this endpoint as `text/event-stream` with a 3s
polling fallback; the payload shape is not in the REST contract (it is a generic `type: string`),
so this plan defines that shape in `contracts/sse-protocol.md` as a Phase 1 output, not as a
reopening of the existing contract.

**Open risk**: the feasibility of keeping a CSP response open for the entire duration of a run
(which can exceed minutes) within IRIS's private web server's default timeout limits MUST be
validated against a real instance — HANDOFF already lists this literally ("SSE and asynchronous
dispatch require technical validation on the target IRIS instance").

## R-011 — Transactions, consistency, and concurrency

**Decision**: Two explicit transactional boundaries, both `TSTART`/`TCOMMIT` (with `TROLLBACK` on
any failure before commit):

1. **Flow save** (`POST`/`PUT /flows`): the entire graph (steps, edges, joins) plus the
   `revision` increment are written as one unit; the revision-conflict check (FR-006) and the
   acyclicity check (FR-007) happen inside that same transaction, before commit — never after.
2. **Dispatch** (`POST /flows/{flowId}/dispatch`): creating the `Run` plus one `StepRun` per step
   (each with a GUID and `timeQueued`) plus the write to `^sentaiRun` are a single unit, exactly as
   `data-model.md` already requires ("Written inside the dispatch transaction"). `WaveDispatcher`
   only starts as a background job after that transaction commits.

Multi-operator concurrency over the same flow is resolved by optimistic locking via `revision`
(R-003/FR-006), not by a long-lived pessimistic lock — consistent with "single instance" and with
the assumption that multiple operators simultaneously editing the same flow is rare, not the main
path.

**Rationale**: Constitution IV (Errors as Values) requires that a partially written run never be
reported as successful; explicit transactions at the two points where partial state would be
observable (a flow with steps but not all edges; a run with some StepRuns but not all) are the
direct mechanism for that.

## R-012 — Tests per layer

**Decision**: `%UnitTest`, already referenced in `module.xml` (`<UnitTest Name="/tests" Package=
"dc.sample.unittests" Phase="test"/>`) — this plan extends the same mechanism to
`sentai.unittest.*`, with sub-packages mirroring the separation of responsibilities: `model`
(persistence rules and per-entity invariants), `validation` (each `FlowValidator` rule isolated),
`dispatch` (wave eligibility and state transitions, with the `%SYS.WorkQueueMgr`/administrative-API
call replaced by a test double), `rest` (the HTTP contract: status codes, payload shapes, against
`openapi.yaml`), `registry` (the closed step-type catalog). Runnable via
`zpm "test sentai-task -v -only"`, the same pattern `iris.script` already uses for `dc-sample`.

**Rationale**: Reuses the test infrastructure already present in the repository instead of
introducing a new framework (Reproducibility + YAGNI). The sub-package split mirrors exactly the
separation of responsibilities the HANDOFF explicitly asks for.

---

## Technical risks and trade-offs, consolidated

| # | Risk | Impact if the assumption is wrong | Proposed mitigation |
|---|---|---|---|
| 1 | Token validation between `sentai.rest.Dispatcher` and the administrative API's internal mechanism (R-002) | The whole API's authentication would need an alternative mechanism | Documented fallback: validate via an internal call to `GET /api/admin/info` |
| 2 | Edge ordering for flows scheduled recurrently (R-007/OQ-1) | Steps of a scheduled flow could run out of order or be duplicated | Assumption explicitly recorded; the first thing to confirm against a real HANDOFF or a live instance |
| 3 | SSE connection duration within IRIS's private web server limits (R-010) | Live events would need to fall back entirely to the 3s polling | The polling fallback is already part of the contract; SSE is an enhancement, not a hard dependency of any FR |
| 4 | Mapping each real `%SYS.Task.*` type to an asynchronous administrative endpoint equivalent to the validated `database-dir/integrity-check` (R-005) | Only `integrity-check` has real evidence; the other 4 real types assume the same API pattern, not individually confirmed | Validate each corresponding asynchronous endpoint against the target instance before implementing its step type |

None of these risks block planning — each has a default decision documented above and an explicit
mitigation path, so none of them becomes a `NEEDS CLARIFICATION` item in `plan.md`'s Technical
Context.
