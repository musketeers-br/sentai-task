---

description: "Task list for the Canvas UI tracer-bullet slice"
---

# Tasks: Canvas UI — Tracer Bullet

**Input**: Design documents from `/specs/002-canvas-ui/` — `plan.md`, `research.md`,
`data-model.md`, `quickstart.md`, `contracts/tracer-bullet-deployment.md`,
`contracts/tokens.json`, `contracts/ui/UI-001-flow-canvas.md`, `contracts/ui/UI-006-design-system.md`

**Prerequisites**: `plan.md` (required)

**Scope**: This plan revision implements **only** the tracer bullet — a multi-stage Docker
build that compiles a SvelteKit + Svelte Flow app and serves it as static assets from a
container built `FROM` the IRIS Community base image, rendering a fixed 3-node/1-edge graph.
Composition, validation, dispatch, live run, WQM, JSON persistence, import/export, and the
theme switch are **not** in scope for these tasks — see `research.md` §Deferred to a later
phase. `spec.md`'s User Stories 1–6 are the full-product backlog; none of them is implemented
by this task list. The tracer bullet is itself the plan's single verifiable increment
(Constitution Principle V), labelled **[US1]** below for checklist-format compliance only.

**Tests**: One Playwright smoke test is required by `contracts/tracer-bullet-deployment.md`
(test-first, per the user's explicit ordering). No other test tier is in scope.

**Organization**: Phase 1 (Setup) and Phase 2 (Foundational) are infra prerequisites shared by
the whole slice. Phase 3 is the tracer bullet's own implementation and acceptance
(everything labelled `[US1]`). There is no Polish phase — nothing here is cross-cutting beyond
the tracer bullet itself.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[US1]**: The tracer bullet — this plan's one and only "story" (see Scope above)
- Every task names its exact file path(s)

## Path Conventions

Per `plan.md` §Project Structure: `frontend/` (new, SvelteKit app) at the repository root;
`Dockerfile` and `docker-compose.yml` (existing, modified) also at the repository root. No
`backend/` or `src/dc/*` ObjectScript package is touched.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the `frontend/` SvelteKit project so later stages have something to
build.

- [X] T001 Create `frontend/package.json` — SvelteKit 2, Svelte 5, `@sveltejs/adapter-static`,
      `@xyflow/svelte` v1.x as dependencies; `typescript`, `vite`, `@playwright/test` as dev
      dependencies; `build`/`dev`/`test:e2e` npm scripts.
      **Done when**: `npm install` in `frontend/` completes with no missing-peer errors and
      `package.json` lists exactly these runtime deps (no DevExtreme, no unrelated UI kit).
      **Blocked by**: none.
- [X] T002 [P] Create `frontend/svelte.config.js` configuring `@sveltejs/adapter-static` with
      a fallback-free single-page build (`pages: 'build'`, `assets: 'build'`, `strict: true`)
      and the app's base path set to `/csp/sentai` (matching the full spec's eventual CSP
      application path per `contracts/quickstart.md`, so this path is not renamed in a later
      phase).
      **Done when**: the file exports a valid SvelteKit config object using
      `@sveltejs/adapter-static`; `svelte-kit sync` does not error.
      **Blocked by**: T001.
- [X] T003 [P] Create `frontend/vite.config.ts` with the SvelteKit Vite plugin.
      **Done when**: `vite.config.ts` exports a config that includes `sveltekit()`;
      `npm run build` (once source files exist) picks it up with no config error.
      **Blocked by**: T001.

**Checkpoint**: `frontend/` is a buildable-once-source-exists SvelteKit project targeting
`adapter-static`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The Docker/serving pipeline that every later task's output must flow through.
No tracer-bullet component work can be verified end-to-end until this phase is done.

**⚠️ CRITICAL**: T005 and T006 depend on the frontend producing a `build/` directory, so they
are only *exercisable* once Phase 3 has source to compile — but the Dockerfile/CSP-app
plumbing itself must be written now so Phase 3's route has somewhere to be served.

- [X] T004 Modify `Dockerfile`: add a `node:20` builder stage before the existing IRIS stage
      that runs `WORKDIR /app`, copies `frontend/`, then `npm ci && npm run build`; modify the
      final IRIS stage to `COPY --from=builder /app/build /home/irisowner/dev/frontend-build`
      (or equivalent path reachable by the CSP application in T005). The existing `FROM $IMAGE`
      line and all `ARG`/`ENV` declarations are unchanged; the Node stage is discarded from the
      final image (no `node` binary in the shipped container).
      **Done when**: `docker build .` (once T001–T003 and Phase 3 source exist) shows a
      `node` stage running `npm ci`/`npm run build`, and `docker history` on the final image
      shows no Node runtime layer.
      **Blocked by**: T001, T002, T003.
- [X] T005 Configure the CSP web application that serves the tracer bullet: add a
      `CreateApplication:Name=/csp/sentai,Path=/home/irisowner/dev/frontend-build,...` action
      (physical path matching T004's copy destination, "Serve files" enabled, no dispatch
      class) to `merge.cpf`, or add the equivalent `##class(Security.Applications).Create()`
      call to `iris.script` under the `IRISAPP` namespace section — whichever the existing
      merge/script convention in this repo favors. Grant unauthenticated read access to static
      files only (no SysAdmin token, no `SENTAI.REST.Dispatcher` involvement — out of scope
      per `research.md`).
      **Done when**: after container start, `http://localhost:52773/csp/sentai/` returns HTTP
      200 for the built `index.html`, with no `/api/admin/*` or `/csp/sentai/api/v1/*` call
      involved in serving it.
      **Blocked by**: T004.
- [X] T006 Review `docker-compose.yml` against the new `Dockerfile` build stage and the CSP
      app path from T005; adjust only if the build context, published ports (1972, 52773,
      53773), or the `./:/home/irisowner/dev` volume mount would shadow the copied
      `frontend-build` directory at container start. If no conflict exists, leave the file
      unchanged and record that in the task's completion note — do not add a second service
      (no Nginx sidecar, per `research.md` R-001).
      **Done when**: `docker-compose config` validates and `docker-compose up -d` starts
      exactly one service (`iris`), with the volume mount not overwriting `frontend-build`.
      **Blocked by**: T004, T005.

**Checkpoint**: The build-and-serve pipeline is wired end to end, ready for the tracer bullet's
own source to flow through it.

---

## Phase 3: Tracer Bullet — Render, Test, Deploy (Priority: P1) 🎯 [US1]

**Goal**: A running container serves one page showing exactly 3 static nodes and 1 static
sequence edge, matching the subset of UI-001/UI-006 this slice targets (title, `#NN` id,
category-coloured left border; `edge.sequence` token at 1.5px with an arrowhead).

**Independent Test**: `contracts/tracer-bullet-deployment.md` items 3–6 — load the served page,
count node/edge DOM elements, inspect the edge's stroke width and colour, confirm no
`/api/admin/*` or `/csp/sentai/api/v1/*` request appears in the network log.

### Fixture and rendering

- [X] T007 [P] [US1] Create `frontend/src/lib/fixtures/tracer-graph.ts` exporting exactly 3
      `TracerNode` literals (`id: "01"|"02"|"03"`, `title`, one `category` each from
      `verification | storage | journal | purge | backup | custom`) and exactly 1
      `TracerEdge` literal (`source`, `target`, both referencing fixture node ids), per
      `data-model.md`. No JSON file, no runtime fetch.
      **Done when**: the module exports a `tracerNodes` array of length 3 and a `tracerEdges`
      array of length 1, typed per `data-model.md`.
      **Blocked by**: T001.
- [X] T008 [P] [US1] Create `frontend/src/lib/design/tokens.ts` re-exporting the `category.*`
      and `edge.sequence` dark-theme values from `contracts/tokens.json` as typed constants
      (e.g. `categoryColor: Record<TracerNode['category'], string>`, `edgeSequence: { width:
      number; color: string }`). Values are copied verbatim from `tokens.json`'s `theme.dark`
      and `edge.sequence` — dark theme only, no light-theme branch, no runtime theme switch.
      **Done when**: the 6 category colours and the sequence-edge width/colour match
      `tokens.json` exactly (`#FF3B4A`, `#3B8DFF`, `#FFC93B`, `#35D07F`, `#FF6FB5`, `#9AA7BC`;
      width `1.5`, colour `#5E6E85`).
      **Blocked by**: T001.
- [X] T009 [US1] Create `frontend/src/lib/canvas/TracerNode.svelte`: a custom Svelte Flow node
      component rendering the title, the `#NN`-formatted id, and a 3px left border coloured
      via `tokens.ts`'s `categoryColor[node.data.category]` (UI-001 §Node anatomy — left
      border only; no hazard band, namespace chip, database directory, timeout, WQM category,
      or handles beyond Svelte Flow's default).
      **Done when**: given a fixture node, the rendered DOM shows the title text, `#01`/`#02`/
      `#03`, and a computed `border-left-color` equal to that node's category token.
      **Blocked by**: T007, T008.
- [X] T010 [US1] Create `frontend/src/lib/canvas/TracerCanvas.svelte`: a Svelte Flow (`
      @xyflow/svelte`) wrapper using its default pan/zoom viewport, registering `TracerNode`
      as the node type for all fixture nodes, and rendering the fixture edge with `type:
      'default'`/`straight'` styled per T011 below. Imports `tracerNodes`/`tracerEdges` from
      T007.
      **Done when**: mounting the component renders a `<svelte-flow>` root containing exactly
      3 node elements and 1 edge element from the fixture.
      **Blocked by**: T007, T009.
- [X] T011 [US1] Style the fixture edge in `frontend/src/lib/canvas/TracerCanvas.svelte` (or a
      colocated `TracerEdge` style/markerEnd config) using `tokens.ts`'s `edgeSequence`:
      stroke width 1.5px, stroke colour `#5E6E85` (dark `edge.sequence`), an arrowhead
      `markerEnd` — the sequence treatment from UI-001/UI-006, explicitly **not** the 2.5px
      join treatment (no join exists in a 1-edge fixture).
      **Done when**: the rendered edge's `<path>` has `stroke-width: 1.5`, `stroke: #5E6E85`,
      and a visible arrowhead marker; no diamond junction marker is present anywhere.
      **Blocked by**: T008, T010.
- [X] T012 [US1] Create `frontend/src/routes/+page.svelte` rendering `TracerCanvas` as the
      page's sole content, plus minimal `frontend/src/app.html` shell if not already
      scaffolded by T001. No palette, no inspector, no top bar, no status bar — none of
      UI-001's other four regions exist in this phase.
      **Done when**: `npm run dev` (or the built output) serves a page whose DOM root contains
      only the `TracerCanvas` render — no other chrome region present.
      **Blocked by**: T010, T011.

### Test (write before the build/deploy verification below)

- [X] T013 [US1] Create `frontend/tests/tracer-bullet.spec.ts` (Playwright): load the served
      page, assert exactly 3 elements match Svelte Flow's node selector and exactly 1 matches
      its edge selector after hydration, assert the edge's computed stroke-width is `1.5` and
      it is not the join treatment, and assert the page's network log contains no request to
      `/api/admin/*` or `/csp/sentai/api/v1/*` — the full checklist from
      `contracts/tracer-bullet-deployment.md` items 4–6. Point the test's base URL at
      `http://localhost:52773/csp/sentai/` so it runs against the deployed container, not the
      Vite dev server.
      **Done when**: the spec file exists and running it against a not-yet-built container
      fails with a connection error (proving the test isn't vacuously passing) — it must not
      yet pass, since nothing is built or deployed at this point.
      **Blocked by**: T012.

### Build and deploy (contract items 1–3, evidence capture)

- [X] T014 [US1] Run `docker-compose build --no-cache` from the repository root. Save the full
      output as `specs/002-canvas-ui/tracer-build.log` (evidence item 1 of
      `contracts/tracer-bullet-deployment.md`).
      **Done when**: the build succeeds, the log shows the `node` builder stage running `npm
      ci && npm run build`, and the final image's base `FROM` line is unchanged from the
      pre-existing `Dockerfile`.
      **Blocked by**: T004, T005, T006, T013.
- [X] T015 [US1] Run `docker-compose up -d`, then run T013's Playwright spec against
      `http://localhost:52773/csp/sentai/` until it passes. Capture
      `specs/002-canvas-ui/tracer-render.png` (screenshot of the rendered canvas) and
      `specs/002-canvas-ui/tracer-network.json` (the page load's network log) as evidence
      items 2 and 3 of `contracts/tracer-bullet-deployment.md`. Run `docker-compose down`
      afterward.
      **Done when**: T013 passes against the live container, `tracer-render.png` visibly shows
      3 nodes with distinct category-coloured left borders and 1 arrowed sequence edge, and
      `tracer-network.json` contains zero entries matching `/api/admin/*` or
      `/csp/sentai/api/v1/*`.
      **Blocked by**: T014.

**Checkpoint**: The tracer bullet is fully deployed and independently verified — this plan
revision's one verifiable increment is complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 (T004 needs `frontend/`'s config files to
  exist so the builder stage has something to `npm ci`/`npm run build`, even though it will
  only *succeed* once Phase 3 adds source). Blocks the deploy tasks in Phase 3 (T014, T015).
- **Phase 3 (the tracer bullet, [US1])**: Fixture/rendering tasks (T007–T012) depend only on
  Phase 1. The test (T013) depends on the full render chain. Build/deploy (T014, T015) depend
  on both Phase 2 (the pipeline) and T013 (the test must exist first, per test-first ordering).

### Within Phase 3

- T007 and T008 are parallel (different files, no interdependency).
- T009 depends on both T007 (fixture types) and T008 (token constants).
- T010 depends on T007 (fixture data) and T009 (node component).
- T011 depends on T008 (edge token) and T010 (canvas component to style).
- T012 depends on T010 and T011 (both must render correctly before the route wraps them).
- T013 depends on T012 (needs a page to load).
- T014 depends on all of Phase 2 plus T013 (test file must exist before the build is
  considered done, per the user's test-first ordering).
- T015 depends on T014.

### Parallel Opportunities

- T002 and T003 (Phase 1) run in parallel once T001 exists.
- T007 and T008 (Phase 3) run in parallel once T001 exists.
- No task in Phase 2 is parallelizable with another Phase 2 task — each modifies infrastructure
  the next one depends on (Dockerfile → CSP app path → compose review).

---

## Parallel Example: Setup and Fixture Tasks

```bash
# Once T001 (package.json) exists, run together:
Task: "Create frontend/svelte.config.js with adapter-static, base path /csp/sentai"
Task: "Create frontend/vite.config.ts with the SvelteKit Vite plugin"

# Once T001 exists (independent of the above), run together:
Task: "Create frontend/src/lib/fixtures/tracer-graph.ts (3 TracerNode + 1 TracerEdge)"
Task: "Create frontend/src/lib/design/tokens.ts (category + edge.sequence dark values)"
```

---

## Implementation Strategy

### MVP = This Entire Task List

There is only one increment in this plan revision. There is no partial-delivery slice smaller
than "the container builds and serves 3 nodes + 1 edge" — that is the tracer bullet's whole
purpose (Constitution Principle V). Complete Phases 1 → 2 → 3 in order; stop and validate at
T015; do not proceed to any of `spec.md`'s User Stories 1–6 until a follow-up plan revision
designs them (see `research.md` §Deferred to a later phase).

### Explicitly out of scope for these tasks

Per the plan's tactical constraint: no palette, no inspector, no validation, no dispatch, no
WQM screen, no theme switch, no `SENTAI.*` ObjectScript class, no JSON persistence, no
import/export, no Nginx sidecar, no Node runtime in the shipped container.

---

## Notes

- [P] tasks touch different files and have no incomplete-task dependency.
- [US1] marks every task belonging to the tracer bullet — the plan's sole story.
- Dark theme only: every colour value above is copied from `tokens.json`'s `theme.dark` /
  `edge.sequence` (no `light` key is read).
- Commit after each task or logical group; stop at the Phase 3 checkpoint to validate the
  whole slice against `contracts/tracer-bullet-deployment.md` before considering this plan
  revision done.

## Completion notes (2026-09-23)

All 15 tasks done; T013 passes against the live container. Deviations from the task text:

- **T004/T006** — build output is copied to `/opt/sentai-web`, not
  `/home/irisowner/dev/frontend-build`: the `./:/home/irisowner/dev` bind mount in
  `docker-compose.yml` would shadow anything baked under that path (the exact conflict T006
  asks to check). `docker-compose.yml` unchanged. The `ARG IMAGE` block also had to move above
  the new builder `FROM` so it stays in global scope for the IRIS stage.
- **T005** — app created in `iris.script` (`AutheEnabled=64`, `ServeFiles=1`, `Recurse=1`). The
  bare path `/csp/sentai/` returns 404: `ServeFiles` has no directory-index resolution, so the
  served URL is `/csp/sentai/index.html`. Recorded in
  `contracts/tracer-bullet-deployment.md` §Deviation.
- **T008** — `tokens.ts`/`tokens.css` are generated from `contracts/tokens.json` by
  `frontend/scripts/generate-tokens.mjs` (runs on `predev`/`prebuild`, output gitignored),
  carrying both themes rather than a hand-copied dark subset, so later phases don't re-copy
  values.
- **T011** — the sequence-edge stroke is applied through a global CSS rule on
  `.svelte-flow__edge-path` (`--edge-sequence-*` tokens); `@xyflow/svelte`'s per-edge `style`
  string did not reach the rendered `<path>`.
- **T014/T015** — evidence lives in `specs/002-canvas-ui/evidence/` (the directory spec.md's
  Evidence Contract names). The container was left running for the next phase instead of
  `docker-compose down`.

## Follow-on: User Story 1 — Flow Composition (2026-09-23)

Implemented against the live `SENTAI.REST.Dispatcher` (spec 003), superseding the tracer
fixture. Verified by `frontend/tests/us1-flow-composition.spec.ts` (Q1, Q2) against the deployed
container, plus 27 vitest unit tests on the pure graph/document/wire logic. Evidence:
`evidence/q1-flow-composition.png`, `evidence/q2-node-anatomy.png`.

Delivered: sign-in with proactive 60 s token refresh (FR-034, in memory only); palette fed by
`GET /catalog/step-types` (the registry is never duplicated client-side); drag-to-place with 8 px
snap (click/Enter adds too, for keyboard users); full node anatomy (FR-006, FR-007, FR-011
hazard band + seal); edge drawing with cycle/self/duplicate rejection at draw time (FR-002,
FR-003); one shared junction diamond per fan-in target and diamond join handle (FR-004); 1.5/2.5
px edge widths (FR-005); edge legend; zoom/fit/lock controls (FR-017); 168×104 minimap in category
colours (FR-018); status-bar counts (FR-009 counts part); dark/light switch via `data-theme`
(FR-038); create/save through `POST`/`PUT /flows` with revision check and canvas geometry.

Deviations, each deliberate:

- **Route** — a flow is addressed as `index.html?flow=<id>`, not `/flows/[id]`: `ServeFiles` has no
  SPA fallback (see `contracts/tracer-bullet-deployment.md` §Deviation). A SvelteKit `reroute`
  hook (`frontend/src/hooks.ts`) maps `…/index.html` onto the root route for the client router.
- **Save flow** button in the top bar — UI-001's vocabulary has none, but nothing else persists
  the canvas yet. *Validate flow* / *Schedule in Task Manager* arrive with US2/US3.
- **Node footer** shows `wqm: <category>` rather than `wqm: N workers`: the worker count needs the
  WQM category read that US5 brings.
- **Inspector** region (FR-014–FR-016) and the precondition panel (FR-008) are US2.
- **Sign-in screen** — not in the design export, required by the token model.

Backend defects found by these tests and fixed in `src/sentai/rest/Dispatcher.cls`:

- `ShapeFlow` omitted `steps[].parameters` (in the openapi `Step` schema), so a read → save round
  trip dropped `daysToKeep` and the flow stopped validating. Regression test:
  `sentai.unittest.rest.FlowsTest:TestReadReturnsStepParameters`.
- No `CHARSET`/`CONVERTINPUTSTREAM`: UTF-8 request bodies were read as Latin-1, persisting any
  non-ASCII name as mojibake ("—" → "â€""). Covered over real HTTP by Q2.

## Follow-on: User Stories 2 and 3 — Inspector, Validation, Schedule (2026-09-24)

Verified by `frontend/tests/us2-inspector-validation.spec.ts` (Q3, Q4) and
`frontend/tests/us3-schedule.spec.ts` (Q5, both outcomes) against the deployed container; 33 vitest
unit tests. Evidence: `evidence/q3-inspector.png`, `q4-validation-report.json`,
`q4-status-bar.png`, `q5-schedule.json`.

Delivered: inspector with the five bound sections and real labelled inputs (FR-014–FR-016),
type-specific parameters for what the validator checks (`daysToKeep`; `customClass` for custom),
WQM category suggestions from `GET /wqm/categories`; destructive block with consequence text and the
typed-confirmation control (FR-011); *Validate flow* (saves first, since validation reads the
persisted flow — FR-019) with the precondition panel on the node (FR-008), per-step error panel, and
status-bar counts in the bound format (FR-009); *Schedule in Task Manager* dialog posting to
`/schedule`, blocked while known errors exist and not by warnings (FR-010, US3 scenario 2).

Deviations, each deliberate:

- **OUTPUT** reads `step04.guid → ^sentaiRun(runGuid,"04")` — the global the backend really writes
  (`sentai.dispatch.WaveDispatcher`), not the contract's `^SentaiRun(runId,"04")`; global names are
  case-sensitive, so the contract spelling would send an operator to an empty global.
- **Typed-confirmation checkbox** is shown checked *and disabled*: dispatch always requires it for
  destructive steps (SC-006), so it is a statement, not a setting.
- **Error panel on nodes** is an addition to UI-001 (which only draws the warning panel) so an error
  can be located without leaving the canvas (SC-002).
- **Only graph changes clear the report**; moving a node or renaming the flow keeps it.
- **`nextRun`** is shown as the backend returns it. The backend does not yet turn `scheduleSpec` into
  native `%SYS.Task` timing (spec 003 HANDOFF, open follow-up), so the value is currently "now".
- **`/data/READONLY_DEMO/`** is a root-owned, read-only directory baked into the image (`Dockerfile`)
  as the acceptance/demo fixture for the precondition warning on a real instance.

Backend defect found and fixed: `sentai.model.Category.SatisfiesInvariant` compared
`maxWorkers <= maxTotalWorkers` even when `maxTotalWorkers = 0`, which `Config.WorkQueues` defines as
"no limit" ("if non-zero, specifies the maximum"). Every step on the built-in `Default` category
therefore failed validation — and dispatch — once `GET /wqm/categories` had mirrored it. Regression
test: `sentai.unittest.validation.CategoryInvariantTest:TestZeroMaxTotalWorkersMeansNoCeiling`.
