# Phase 0 — Research

Feature: `001-flow-orchestrator` · Date: 2026-09-21

Every entry states the decision, why it was taken, and what was rejected. Items still
open are collected at the end and mirrored in `spec.md`.

---

## R-001 · Canvas library

**Decision**: `@xyflow/svelte` (Svelte Flow) with custom node and edge components.

**Rationale**: It gives pan/zoom, handles, a minimap and controls out of the box, and
its node/edge API is component-based, so the designed node card is written as ordinary
Svelte markup rather than fought against. The design vocabulary in the contracts —
handles, bezier edges, minimap — was chosen to match this library, so the mapping is
one to one.

**Alternatives rejected**: hand-rolled SVG canvas (weeks of pan/zoom and hit-testing for
no gain); `svelvet` (smaller ecosystem, edge customisation weaker); embedding a React
flow library through an interop shim (two runtimes in one bundle).

---

## R-002 · Rendering the fan-in edge

**Decision**: A custom edge component that renders the bezier path plus a junction
diamond, selected by an `isJoin` flag computed from the target's incoming-edge count.
Stroke widths and the marker geometry are fixed in `contracts/tokens.json`.

**Rationale**: Svelte Flow edges are components, so the whole fan-in treatment —
thicker stroke, shared junction marker, diamond target handle — is one component and one
derived boolean. The join marker is drawn once per target, not once per edge, so three
incoming edges produce one diamond.

**Alternatives rejected**: an invisible "join node" between the sources and the target
(pollutes the graph model and the data model with a node the operator never created);
edge labels (illegible at zoom-out, which is exactly when the shape of the wave matters).

---

## R-003 · Creating scheduled tasks in IRIS

**Decision**: The flow compiler instantiates `%SYS.Task` rows programmatically, one per
step, each pointing at a `%SYS.Task.Definition` subclass shipped in the `SENTAI.Task`
package, with the orchestration metadata (flow id, revision, step id, join inputs)
carried as task properties.

**Rationale**: Constitution V. The tasks remain first-class Task Manager entries —
visible, suspendable and runnable from the Management Portal, and surviving uninstall of
the UI. Writing the wave metadata onto the task means the dispatcher can reconstruct the
graph from the instance alone, with no dependency on the UI's own store being intact.

**Alternatives rejected**: a single umbrella task that internally sequences everything
(one opaque row in the portal, no per-step visibility, no per-step cancel); an external
scheduler (violates Constitution V outright).

---

## R-004 · GUID generation and correlation

**Decision**: The dispatcher generates the GUID (`$SYSTEM.Util.CreateGUID()`) **before**
the step starts, writes it to `^SentaiRun(runId, stepId)` inside the same transaction
that marks the step queued, and returns it synchronously from the dispatch call.

**Rationale**: Constitution III. Generating after the start creates a window in which a
running step has no identity — exactly the window in which an operator wants to cancel
it. Generating before, and persisting transactionally, means an orphan is impossible: a
GUID with no run row cannot exist.

**Alternatives rejected**: using the Task Manager's own task-history id (assigned after
the fact, and reused across runs); a client-generated UUID (two authorities for the same
identifier).

---

## R-005 · Live state transport

**Decision**: Server-Sent Events from a dedicated REST endpoint, with a 3-second polling
fallback when the gateway or a proxy strips the stream.

**Rationale**: State flows one way, from server to client; SSE is the simplest thing that
meets NFR-001 and reconnects on its own. It survives the IRIS web gateway without the
upgrade handshake a WebSocket needs, and it degrades to polling without a second code
path on the server — the fallback re-reads the same projection.

**Alternatives rejected**: WebSocket (bidirectional machinery for a unidirectional
problem, and more to configure at the gateway); polling only (either misses
NFR-001 or hammers the instance during a maintenance window, which is when the
instance can least afford it).

---

## R-006 · Precondition evaluation

**Decision**: Preconditions are evaluated per step type by an evaluator class in
`SENTAI.Precondition`, at three moments: on canvas validation (on demand), before
scheduling, and again at dispatch. The dispatch-time evaluation is authoritative.

**Rationale**: The canvas warning exists to let the operator fix the problem in advance;
it cannot be authoritative because hours pass between composing and running, and a
database can be dismounted in between. Re-evaluating at dispatch is what turns a warning
into a refusal to start, with a reason naming the condition.

**Alternatives rejected**: evaluating only at dispatch (no warning while composing —
the operator finds out at 03:00); caching the canvas result (stale by construction).

---

## R-007 · WQM category semantics

**Decision**: One category per flow by default, named after the flow
(`SENTAI.<FLOWNAME>`), configurable per step. The four ceilings are surfaced exactly as
IRIS defines them and are not reinterpreted.

**Rationale**: Constitution IV. The DBA already knows what `MaxActiveWorkers` means; a
friendlier synonym would break the correspondence with the Management Portal and with
the IRIS documentation they will consult when it misbehaves. The UI's contribution is
explaining the *effect* at the point of edit and drawing how the ceilings nest — not
renaming them.

**Alternatives rejected**: a single "intensity" slider mapping to all four (hides the
model, and produces combinations the DBA cannot reason about); leaving the fields bare
as the portal does (the effect of each is the part that is genuinely hard).

---

## R-008 · Visual regression against the screen contracts

**Decision**: Playwright screenshots at the contract viewport, `deviceScaleFactor: 2`,
compared structurally rather than pixel-exactly: layout regions, presence of the state
shapes, text content and contrast are asserted; a pixel diff runs with a 0.3 % tolerance
as a change detector, not as a gate.

**Rationale**: The PNGs bind structure, states and vocabulary, not antialiasing. A strict
pixel gate fails on a font-hinting change and trains the team to regenerate baselines
without looking, which destroys the contract's value.

**Alternatives rejected**: strict pixel equality (brittle, and the first red build gets
the tolerance raised to 100 %); no visual test at all (the contract then binds nothing).

---

## R-009 · Theming mechanism

**Decision**: CSS custom properties defined twice — once under
`:root:not([data-theme="dark"])` and once under `:root[data-theme="dark"]` — generated
from `contracts/tokens.json` at build time. No `filter: invert`, no runtime colour maths.

**Rationale**: Constitution VI. Generating both ramps from one source file makes the
independence auditable: a reviewer can see that the dark value of a token is not a
function of the light one.

**Alternatives rejected**: a single palette with computed lightness (that *is* the
inversion the constitution forbids); duplicating values by hand in two stylesheets (they
drift).

---

## R-010 · Pause semantics

**Decision**: *Pause* means "stop dispatching further work units for this step"; it is
offered only on step types whose underlying implementation can honour it, and the control
is absent — not disabled — on types that cannot.

**Rationale**: IRIS has no universal suspend for a task already executing. Offering a
greyed-out button on a step that can never pause is a promise the product cannot keep at
exactly the wrong moment.

**Open**: which of the shipped step types can honour it. Carried to the open items below.

---

## Open items

| # | Question | Blocks | Proposed default |
|---|---|---|---|
| O-1 | Is the join's partial-failure policy per-join or per-flow, and what is the default? | FR-025, UI-002 | Per-join, default *block on any failure*; the designed screen shows a wave where it was set to proceed |
| O-2 | Must v1 address a mirror set or an ECP cluster? | Whole spec | Single instance in v1 |
| O-3 | Which step types can honour *pause*? | R-010, FR-024 | Purge-family only; integrity check and journal switch expose no pause control |
| O-4 | Retention of run history — how long, and who purges it? | data-model | 90 days, purged by a SentaiTask flow, dogfooding the product |

These four are decisions for the product owner, not research questions. Everything a
prototype needs is settled above.
