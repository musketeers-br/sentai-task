# Phase 0 — Research

Feature: `002-canvas-ui` · Plan slice: **Tracer Bullet** · Date: 2026-09-21

This research covers only the tracer-bullet slice ordered for this plan: prove that a
SvelteKit + Svelte Flow application can be built by a multi-stage Dockerfile and served as
static assets from a container built FROM the IRIS Community base image, rendering a fixed
3-node/1-edge graph. It does **not** research the full spec 002 surface (composition,
validation, dispatch, live run, WQM, theming toggle) — those remain `NEEDS CLARIFICATION` for a
later plan revision and are listed under **Deferred to a later phase** at the end of this file.

---

## R-001 — Static asset serving: IRIS private web server vs. a Nginx sidecar

**Decision**: Serve the SvelteKit static build output directly from the IRIS Community
container's own private web server, as a CSP application with "Serve files" enabled and its
physical path pointed at the copied `build/` output. No second server process is added to the
container.

**Rationale**: The project's existing `Dockerfile` already builds `FROM` an IRIS Community
image (contest rule: the shipped artifact must be a container built from that base image), and
IRIS's private web server serves static files out of the box via a CSP application's physical
path — no extra software to install, no second process to supervise, and no second port to
expose beyond the one IRIS already publishes (52773). For a tracer bullet whose only job is to
prove the pipeline, adding a reverse proxy is complexity the phase does not need (YAGNI, per the
Constitution's Engineering Standards).

**Alternatives considered**:
- **Nginx inside the same container, reverse-proxying to IRIS's management API and serving
  static files itself.** Rejected for this phase: introduces a second process (and a process
  supervisor to keep both alive) purely to serve files IRIS can already serve, for no capability
  this phase needs. Revisit only if a later phase needs SPA client-side routing with a wildcard
  fallback that the CSP application's static file serving cannot express cleanly (see R-003).
- **Nginx as a separate container in `docker-compose.yml`, in front of IRIS.** Rejected: the
  contest artifact is a single container built from the IRIS Community image; a second container
  is not part of the delivered shape.

## R-002 — SvelteKit adapter

**Decision**: `@sveltejs/adapter-static`, producing a fully static `build/` directory (HTML,
JS, CSS, and any bundled fixture data) with no Node server required at runtime.

**Rationale**: The tracer bullet renders a hardcoded fixture with no backend calls, so there is
nothing for a Node SSR runtime to do at request time. A static adapter matches the constraint
"serve the static assets via Nginx/IRIS" literally, and it keeps the final container free of a
Node process — only IRIS runs there.

**Alternatives considered**:
- **`adapter-node`**: rejected. Would require running `node build/index.js` inside the
  container alongside IRIS, contradicting the "static assets" framing of this plan and adding a
  process the tracer bullet does not need.
- **`adapter-auto`**: rejected as a permanent choice; it defers the decision rather than making
  it, and the target (a non-Node container) is already known.

## R-003 — Routing shape for this phase

**Decision**: One prerendered page (SvelteKit's default root route) renders the whole tracer
bullet. No dynamic routes (`/flows/[id]`, `/runs/[guid]`, `/wqm/[category]` from the full spec)
are wired up in this phase.

**Rationale**: The full spec's routes require data that does not exist yet (a saved flow, a run
GUID, a category) and a backend call this phase explicitly excludes. A single static route
avoids the open question of SPA fallback routing (an unknown path resolving to `index.html`)
that a CSP static-file application would need extra configuration to express — that question is
deferred, not resolved, by scoping to one route now.

**Alternatives considered**:
- **Implement `/flows/[id]` as static-exported with a hardcoded `id`.** Rejected: adds a routing
  layer and a fallback-page question for zero behavioral gain over a single root route, when the
  fixture is hardcoded either way.

## R-004 — Canvas library and node scope

**Decision**: `@xyflow/svelte` (Svelte Flow) v1.x, using its default pan/zoom viewport and one
custom node component that renders only the fields needed to distinguish 3 static nodes: title,
`#NN` id, and the step-type category colour on the left border (per
[UI-006](contracts/ui/UI-006-design-system.md) and [`tokens.json`](contracts/tokens.json)).

**Rationale**: Confirms the rendering library itself compiles and runs inside the static-adapter
build and inside the served container — the actual risk this tracer bullet exists to retire.
The full node anatomy (hazard band, namespace chip, database directory, timeout, WQM category,
handles, inspector wiring) is UI-001's contract for a later phase; drawing all of it now, with no
inspector or palette behind it, would be presentation without the capability it implies.

**Alternatives considered**:
- **Render the graph with a hand-rolled SVG, deferring Svelte Flow entirely.** Rejected: it
  would not retire the actual risk (does Svelte Flow build and ship correctly through this
  Docker pipeline?) and the full spec already commits to Svelte Flow as the canvas engine.

## R-005 — Fixture data shape

**Decision**: The 3 nodes and 1 edge are a hardcoded TypeScript literal (not fetched, not read
from a file at runtime), colocated with the Svelte Flow wrapper component. No JSON file is read
by the server or the client at runtime.

**Rationale**: Matches the explicit exclusion of JSON persistence for this phase; a compiled-in
literal is the smallest thing that can prove rendering without implying a persistence layer that
does not exist yet.

**Alternatives considered**:
- **A static `.json` fixture imported at build time.** Considered equivalent in spirit (still no
  runtime persistence) but rejected for this phase to avoid any appearance of a "flow file
  format" decision, which is explicitly a later-phase concern (import/export).

---

## Deferred to a later phase (not researched here)

These remain open and are **not** resolved by this plan revision. They correspond to the
functional requirements in `spec.md` beyond the tracer-bullet slice, and to capabilities the
user's tactical constraint explicitly named as out of scope for this plan:

- **Reactive properties**: drag-and-drop composition from the palette (FR-001), edge drawing and
  cycle rejection (FR-002, FR-003), the inspector (FR-014–FR-016), validation (FR-019), live-run
  polling/streaming and token refresh (FR-032, FR-034), and the WQM screen's recomputing
  prediction sentence (FR-035) all require client-side reactive state and, for most, a backend
  call. None are designed by this plan.
- **JSON persistence**: `SENTAI.Model.Flow/Step/Edge` persistence, `flow-definition.schema.json`
  as a save/load format, and the `^SentaiRun` GUID registry are contracts.md-level artifacts
  this plan does not implement or provision a database for.
- **Import/export**: no flow import or export mechanism is designed or implied by the fixture
  data format chosen in R-005.
- **The `SENTAI.REST.Dispatcher` API surface and the SysAdmin API auth/refresh cycle**
  (Clarifications 2026-09-21, FR-034): no network call exists in this phase, so there is nothing
  to authenticate yet.
- **Theming toggle**: the tracer bullet renders the dark theme's tokens only (the product
  default per UI-006); the `Dark`/`Light` switch and UI-007's parity requirements are not wired
  up.

A follow-up plan revision (or a `plan-002.md` phase) must pick these up before `/speckit-tasks`
can decompose the rest of spec 002's user stories.
