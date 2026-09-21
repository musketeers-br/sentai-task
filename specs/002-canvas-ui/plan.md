# Implementation Plan: Canvas UI — Tracer Bullet

**Branch**: `002-canvas-ui` | **Date**: 2026-09-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-canvas-ui/spec.md`

**Tactical constraint (this plan revision only)**: this plan does not attempt spec 002's full
scope. It implements a single **tracer bullet**: prove that a SvelteKit + Svelte Flow
application builds via a multi-stage Dockerfile and serves as static assets from a container
built FROM the IRIS Community base image, rendering a fixed 3-node/1-edge graph. Reactive
properties (drag-and-drop, edge drawing, the inspector, validation, live run, WQM), JSON
persistence, and import/export are explicitly **next phases**, out of this plan's scope. See
`research.md` §Deferred to a later phase for the full list against spec.md's FR numbers.

## Summary

The primary requirement of spec 002 is a five-screen flow-composition-and-execution surface
(UI-001, UI-002, UI-005, UI-006, UI-007) backed by `SENTAI.*` ObjectScript persistence and
dispatch. That is a multi-week build. This plan revision instead retires the single riskiest
unknown first, per the user's tactical constraint and Constitution Principle V (Verifiable
Increments): can the chosen frontend stack (SvelteKit + Svelte Flow) actually be compiled by a
multi-stage Docker build and served from a container built on the IRIS Community base image at
all? The technical approach is: a Node builder stage runs `npm run build` against
`@sveltejs/adapter-static`; the existing IRIS-based final stage copies the static output into a
CSP application directory that IRIS's own private web server serves — no Nginx process, no
second container. The rendered page shows exactly 3 static nodes and 1 static edge, matching
UI-001's node-anatomy and sequence-edge treatment for those fields only. No backend call, no
persistence, no import/export exists in this slice — see `research.md` for why, and for what is
deferred.

## Technical Context

**Language/Version**: TypeScript 5.x, Svelte 5 (runes) via SvelteKit 2. Node 20 LTS is used only
in the Docker build stage; no Node process runs in the shipped container.

**Primary Dependencies**: SvelteKit 2 with `@sveltejs/adapter-static` (R-002); `@xyflow/svelte`
(Svelte Flow) v1.x, used for its default viewport and one custom node component (R-004). The
`SENTAI.*` ObjectScript classes and the SysAdmin/`SENTAI.REST.Dispatcher` APIs are **not**
dependencies of this slice — no network call exists in the tracer bullet.

**Storage**: N/A. The 3 nodes and 1 edge are a compiled-in TypeScript literal (R-005); no
database, no JSON file read at runtime, no `SENTAI.Model.*` persistence.

**Testing**: Playwright, one smoke test per the tracer-bullet deployment contract
([`contracts/tracer-bullet-deployment.md`](contracts/tracer-bullet-deployment.md)): load the
served page, assert node/edge element counts and the sequence-edge treatment, assert no request
to `/api/admin/*` or `/csp/sentai/api/v1/*`.

**Target Platform**: Linux container built `FROM` the IRIS Community base image already pinned
in the repository's `Dockerfile` (contest rule). Static assets are served by IRIS's private web
server as a CSP application with "Serve files" enabled (R-001) — no Nginx sidecar, no second
container in `docker-compose.yml`.

**Project Type**: Web application (frontend + IRIS backend container). This plan's slice touches
only the frontend build/deploy path and the `Dockerfile`; the ObjectScript backend directory
structure is unaffected and no `SENTAI.*` class is added by this plan.

**Performance Goals**: None beyond "the container builds and serves the page." No load,
concurrency, or interaction-latency target applies to a non-interactive static render.

**Constraints**: Multi-stage `Dockerfile` only, with the Node builder stage discarded from the
final image (R-002); no DevExtreme (inherited contest rule); no runtime Node process in the
shipped container; no reactive state, no persistence, no import/export (explicit tactical
constraint for this plan revision).

**Scale/Scope**: Exactly 3 static nodes and 1 static edge (`data-model.md`). One route. No
palette, no inspector, no validation, no dispatch, no WQM screen, no theme switch — the dark
theme's tokens are applied as the fixed, only rendering.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Applies to this slice? | Assessment |
|---|---|---|
| I. Layered Architecture | Yes, minimally | No backend exists in this slice to layer against, but the frontend source is still organized so the fixture data (`data-model.md`'s `TracerNode`/`TracerEdge`) is colocated with, but separable from, the Svelte Flow rendering component — so a later phase can replace the fixture with a real API-backed store without restructuring the render layer. No cross-layer shortcut exists because there is only one layer running (presentation); nothing reaches into infrastructure because no infrastructure call exists yet. **Pass.** |
| II. Closed Capability Set | Yes | The tracer bullet executes no user-supplied input of any kind — the fixture is a compile-time literal, not a runtime input. There is no expression field, no dynamic dispatch. **Pass, trivially.** |
| III. Delegated Authorization | N/A this slice | No API call exists, so no authorization decision is made, cached, or inferred by this slice. Deferred, not violated — flagged explicitly in `research.md` §Deferred so it is not forgotten when the next phase adds the first API call. |
| IV. Errors as Values | N/A this slice | A static render with no backend call has no predictable-failure path to represent as a value yet (a failed `docker build` or a 404 are build/ops concerns, not application-layer results). Deferred, not violated. |
| V. Verifiable Increments | Yes — this is the organizing principle of this plan revision | The tracer bullet is itself the verifiable increment: a user (or the Playwright smoke test standing in for one) can observe the built container serving 3 nodes and 1 edge end-to-end. It is sliced by observable behavior (a working deployment pipeline), not by technical layer. **Pass.** |
| VI. Technology Agnosticism | Yes | SvelteKit, Svelte Flow, and the IRIS Community base image are Plan-level choices, justified in `research.md` against the principles above; none is asserted as a constitutional rule. **Pass.** |

No violations requiring justification. **Complexity Tracking is empty.**

## Project Structure

### Documentation (this feature)

```text
specs/002-canvas-ui/
├── plan.md                          # This file
├── research.md                      # Phase 0 output — tracer-bullet decisions + deferred list
├── data-model.md                    # Phase 1 output — TracerNode/TracerEdge fixture only
├── quickstart.md                    # Phase 1 output — build/run/verify steps
├── contracts/
│   ├── tracer-bullet-deployment.md  # Phase 1 output — this slice's checkable surface
│   ├── README.md                    # Pre-existing — full spec's binding design contracts
│   ├── tokens.json                  # Pre-existing — used for the 3 nodes' category colours
│   ├── openapi.yaml                 # Pre-existing — not implemented by this slice
│   ├── data-model.md                # Pre-existing — full entity model, not built by this slice
│   ├── screens/*.png                # Pre-existing — full-screen contracts, not targeted this slice
│   └── ui/UI-00*.md                 # Pre-existing — UI-001/UI-006 partially referenced (node anatomy subset, edge token)
└── checklists/requirements.md       # Pre-existing
```

### Source Code (repository root)

```text
frontend/                     # NEW this slice
├── src/
│   ├── lib/
│   │   ├── canvas/
│   │   │   ├── TracerCanvas.svelte   # Svelte Flow wrapper: viewport + one custom node component
│   │   │   └── TracerNode.svelte     # Renders id, title, category-coloured left border only
│   │   └── fixtures/
│   │       └── tracer-graph.ts       # The 3 TracerNode + 1 TracerEdge literal (data-model.md)
│   ├── routes/
│   │   └── +page.svelte              # The one route; renders TracerCanvas
│   └── app.html
├── static/
├── svelte.config.js                  # adapter: @sveltejs/adapter-static
├── vite.config.ts
├── package.json
└── tests/
    └── tracer-bullet.spec.ts         # Playwright smoke test (contracts/tracer-bullet-deployment.md)

Dockerfile                    # MODIFIED: Node builder stage added ahead of existing IRIS stage
docker-compose.yml            # UNCHANGED: no new service
src/dc/sample/                # UNCHANGED: pre-existing ObjectScript dev-template sample, untouched
```

**Structure Decision**: Web-application shape (frontend + IRIS container), but this plan's
slice adds only the `frontend/` tree and modifies `Dockerfile`. No `SENTAI.*` ObjectScript
package is created — the full backend (`SENTAI.Model.Flow/Step/Edge/Run/StepRun/Category`,
`SENTAI.Dispatch.WaveDispatcher`, `SENTAI.REST.Dispatcher`, `^SentaiRun`) remains contract-only
in `contracts/data-model.md` until a later phase's plan revision designs it.

## Complexity Tracking

No Constitution Check violations. This section intentionally left empty.
