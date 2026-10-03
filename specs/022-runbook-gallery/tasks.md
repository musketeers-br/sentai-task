# Tasks: Runbook Gallery — Named Ready-Made Flows Instead of the Empty Canvas

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/runbook-gallery.md](contracts/runbook-gallery.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD, Constitution V). vitest on the pure modules (`npm test`, plus
`npm run check` after every frontend change); Playwright in
`frontend/tests/us31-runbook-gallery.spec.ts` against the **baked** bundle
(`bash scripts/publish-canvas.sh` after the last build), evidence into
`specs/022-runbook-gallery/evidence/`; IRIS: `zpm "load /home/irisowner/dev"` then
`zpm "test sentai-task -only"` in namespace `IRISAPP` (268 → **269** methods; the REST tests'
raw JSON output is expected noise). `iris_*` MCP tools answer for `USER` — pass
`namespace: "IRISAPP"`.

**Hard rules**:

- The curated set is **exactly seven cards** (the six the spec names + the example as a card,
  FR-002/FR-013; Q1 answer A is normative). More runbooks enter only through the ordinary change
  process — no authoring UI, no runtime extension (Constitution II).
- **Use is create-or-open by `flowName`** (FR-006): the platform's name index is the only
  "already used" memory — no local record, no copy-with-suffix, no `localStorage`/`sessionStorage`
  key anywhere in the feature (Constitution III).
- **No backend product change** (FR-014): `src/sentai/**` is untouched except
  `tests/sentai/unittest/demo/DemoTest.cls`, which gains **one test method**. No new endpoint, no
  wire change, no demo-setup or reset change.
- The three shared definitions are **two-sided fixture-synced** ([research R-2](research.md)):
  editing the example, weekly-window or cross-server definition means editing
  `tests/fixtures/{example-flow,weekly-window-flow,showcase-flow}.json` in the same change —
  vitest and `DemoTest` both fail otherwise.
- Card verdicts derive only from catalog + target **data** (never a cached permission); anything
  else the platform refuses surfaces **verbatim** (FR-009, Constitution III/IV).
- The gallery never renders over a platform state: the unreadable panel, refusals, unreachable
  and the sign-in overlay keep their precedence (FR-001 edge cases, Constitution IV).
- All new user-facing text is English (FR-017); **Use** is the label for the input's *Usar*;
  testids and slugs come from [contracts/runbook-gallery.md](contracts/runbook-gallery.md).
- Every checkpoint must leave the **whole** suite green: the invitation-touching scenarios of
  `us21`/`us30` are adapted in the same task that removes the invitation; `us20` is retired in
  the same task that builds the gallery (guarantee mapping in plan D-9).

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [X] T001 Create branch `feat/spec022` from `master` (the worktree currently holds the finished
  `feat/spec021` session — do not touch it) and confirm `.specify/feature.json` already points at
  `specs/022-runbook-gallery`. **Adapted per the session's "não commit nada" instruction**: no
  branch, switch or commit — the worktree stays on `feat/spec021` with all 022 work uncommitted
  on top; `feature.json` confirmed.
- [X] T002 [P] Baselines for SC-004 in `specs/022-runbook-gallery/evidence/README.md` (create the
  evidence table skeleton from [quickstart.md](quickstart.md)): vitest case count
  (`cd frontend && npm test`), `npm run check` clean, IRIS suite count (268), e2e spec-file count,
  and the date of the last green full e2e run if the stack is up — the "before" the 0-regression
  claim compares against.

---

## Phase 2: Foundational — the curated data and its sync (blocking)

**Purpose**: the seven runbooks as shipped data, proven equal to the shared fixtures on both
sides. Every story consumes this; nothing story-specific lives here.

- [X] T003 [P] Unit tests, failing first (module missing): `frontend/src/lib/flows/runbooks.test.ts`
  per [data-model §1](data-model.md) — exactly 7 runbooks; unique non-empty `flowName`s;
  `definition.name === flowName`; every step type declared **and** available in a reference
  registry fixture; every declared parameter of that type filled (`warnDays` 30 on certificate
  steps, `minFreePercent`/`keepDays` where the row says so); every definition carries
  `canvasGeometry`; deep-equality with `tests/fixtures/example-flow.json`,
  `weekly-window-flow.json` and `showcase-flow.json` for the three shared definitions (the
  `example.test.ts:74-76` comparison pattern); the cross-server `flowName` is
  `"Showcase: nightly checks across servers"`; titles/purposes in English.
- [X] T004 [P] Implement `frontend/src/lib/flows/runbooks.ts`: the `Runbook` type
  ([data-model §1](data-model.md): `title`, `purpose`, optional `suggestedCadence`, `flowName`,
  `definition`) and the `RUNBOOKS` array exactly per the table in [research R-10](research.md) —
  the weekly-window and cross-server rows verbatim from their fixtures (cross-server
  `flowName` = the seeded showcase name), the example row reusing `exampleDefinition()` from
  `frontend/src/lib/flows/example.ts`, and the four new rows authored from declared+available
  types only (nightly sweep: integrity USER ∥ IRISAPP → ALL_MUST_SUCCEED → db-size-report;
  pre-upgrade: security-posture ∥ web-app-inventory ∥ certificate-expiry(30) → ALL_MUST_SUCCEED
  → db-size-report; certificate watch: single certificate-expiry-check `{warnDays: 30}`,
  cadence "daily"; security review: permissions-inventory ∥ security-posture ∥ oauth-inventory,
  no join). T003 passes.
- [X] T005 Add `Method TestWeeklyWindowMatchesFixture()` to
  `tests/sentai/unittest/demo/DemoTest.cls`, mirroring `TestExampleMatchesFixture`/`TestShowcaseMatchesFixture`
  (`DemoTest.cls:60-75`): compare `##class(sentai.demo.DemoFlows).Payload()` with
  `..Fixture("weekly-window-flow.json")` on name, `Fingerprint` and `canvasGeometry` (the fixture
  exists unreferenced today — this puts it to work, [research R-2](research.md)). Proof:
  `zpm "load /home/irisowner/dev"` + `zpm "test sentai-task -only"` green, **269** total.

**Checkpoint**: the data exists and both sides prove it equals the fixtures; stories can start.

---

## Phase 3: User Story 1 — The empty canvas is a gallery of named runbooks (Priority: P1) 🎯 MVP

**Goal**: whenever the Flows canvas is empty with no flow open — saved flows or not — the operator
sees seven cards (name, purpose, mini-graph, **Use**) and *Start from scratch* (FR-001, FR-002,
FR-003, FR-012).

**Independent test**: sign in → Flows with no flow open → `runbook-gallery` visible with 7
`runbook-card`s, each graph showing its definition's node/edge counts; with flows saved (routed
list) the gallery still shows; *Start from scratch* → blank canvas, palette usable.

### Tests first

- [X] T006 [P] [US1] Unit tests, failing first: `frontend/src/lib/flows/miniGraph.test.ts` per
  [data-model §3](data-model.md) — nodes scaled into the fixed viewBox preserving relative
  layout; edges connect source/target border anchors; destructive flags carried; node/edge counts
  equal the definition's steps/edges; a single-node definition yields one node and no edges.
- [X] T007 [P] [US1] Playwright first, failing (no gallery exists): create
  `frontend/tests/us31-runbook-gallery.spec.ts` — (a) no flow open → `runbook-gallery` visible
  with 7 `runbook-card`s, each with title, purpose line, `runbook-card-graph` and
  `runbook-card-use` (FR-001, FR-003); (b) route `GET **/csp/sentai/api/v1/flows` with a
  non-empty list → the gallery **still** shows (the `noFlows` independence, FR-001, SC-001);
  (c) per-card graph counts match the definition (weekly window: 6 nodes / 6 edges; security
  review: 3 / 0); (d) *Start from scratch* → blank canvas, palette drag still works (FR-012);
  (e) region announced "Runbooks", Tab reaches every Use and *Start from scratch* (FR-016).
  In the same task: **retire** `frontend/tests/us20-example-flow.spec.ts` (delete; its
  "offered" guarantee is scenario (a); the idempotence/guard/unavailable guarantees are rebuilt
  in T013/T016 — plan D-9's 1:1 mapping) and adapt the invitation-touching scenarios:
  `us21-getting-started.spec.ts` lines 171-180 and 202-218 and
  `us30-first-time-tour.spec.ts` lines 181-191 now assert the gallery where they asserted
  `example-invitation`.

### Implementation

- [X] T008 [P] [US1] Implement `frontend/src/lib/flows/miniGraph.ts` (`MiniNode`, `MiniEdge`,
  `miniGraph(definition, registry)` per [data-model §3](data-model.md) — pure, no DOM). T006 passes.
- [X] T009 [P] [US1] Create `frontend/src/lib/flows/MiniGraph.svelte` (one card's SVG:
  `runbook-card-graph`, node rects labelled with registry step-type labels, edge segments with
  arrowheads, destructive accent from the palette's destructive styling) and
  `frontend/src/lib/flows/RunbookGallery.svelte` per [contracts/runbook-gallery.md](contracts/runbook-gallery.md):
  `role="region"` name "Runbooks", `data-testid="runbook-gallery"`, one `runbook-card` per
  runbook (carrying `data-runbook="<slug>"` per the contract's slug rule), title, purpose,
  `MiniGraph`, `runbook-card-use` (present; wired in T014), `runbook-card-cadence` iff declared
  (rendered now, verdict-gated display arrives with US3), and `start-from-scratch`.
- [X] T010 [US1] Wire the page in `frontend/src/routes/+page.svelte`: replace the `showInvitation`
  derivation (line 236) with `showGallery = unreadable === null && editor.id === null &&
  editor.steps.length === 0 && !galleryDismissed` (drop the `noFlows` term and the `noFlows` boot
  fact at lines 77/232; rename `invitationDismissed` → `galleryDismissed`), mount
  `RunbookGallery` where `EmptyCanvasInvitation` sits (lines 556-561), pass it the registry and
  the runbooks, and delete `frontend/src/lib/flows/EmptyCanvasInvitation.svelte`. Precedence is
  unchanged: the unreadable panel (lines 563-573) and every non-editing state still win. T007's
  scenarios (a)-(e) pass; `us21`/`us30` (adapted in T007) stay green.

**Checkpoint**: the gallery is the empty canvas; the whole suite is green; the demo value (seven
real graphs on arrival) is shippable on its own.

---

## Phase 4: User Story 2 — Use puts a runnable flow on the canvas in one action (Priority: P1)

**Goal**: one action from a card lands the runbook on the canvas as a saved, runnable flow —
open-or-create by `flowName`, idempotent, guarded over unsaved edits, refusals verbatim
(FR-006, FR-008, FR-009, FR-010).

**Independent test**: Use on *Weekly maintenance window* → the flow opens, its graph matches the
card; *Validate flow* → 0 errors; *Run now* completes. Use again → the same flow (no duplicate).

### Tests first

- [X] T011 [P] [US2] Unit tests, failing first, in `frontend/src/lib/flows/runbooks.test.ts` for
  `useRunbook` (the generalized `openExample` machine, [data-model §4](data-model.md)): existing
  flow by `flowName` → its id, create never called; missing → create called once with the
  definition, its id returned; 409 on create → re-list → the id; refused list or create → the
  refusal passes through unchanged. Plus `frontend/src/lib/flows/guard.test.ts`: the new
  `{ kind: 'runbook'; runbook }` member decides like the others (`needsGuard`/`decide`/`afterSave`
  unchanged in behaviour).
- [X] T012 [P] [US2] Playwright first, failing, appended to
  `frontend/tests/us31-runbook-gallery.spec.ts`: (a) Use on *Weekly maintenance window* → the flow
  is open, the canvas graph matches the card's counts, *Validate flow* → 0 errors, *Run now* →
  steps complete (SC-002); (b) the retired `us20` idempotence guarantee: Use, close, Use again →
  one flow of that name, never a duplicate (FR-006); (c) the retired `us20` guard guarantee:
  dirty canvas + Use → Save / Discard / Cancel first; *Cancel* keeps the editor (FR-008);
  (d) refusal verbatim: route `POST **/csp/sentai/api/v1/flows` to 403 with a problem body →
  the platform's status and reason surface as-is, nothing created (FR-009, SC-003).

### Implementation

- [X] T013 [US2] Implement `useRunbook` in `frontend/src/lib/flows/runbooks.ts` by generalizing
  `openExample` (`frontend/src/lib/flows/example.ts:61-75`): list → find by `flowName`
  case-insensitively → open; else `createFlow`; 409 → re-list; every refusal returned as-is.
  Fold `openExample` into it — `example.ts` keeps `EXAMPLE_FLOW_NAME` and `exampleDefinition()`
  (its fixture test stays), and the page's example path now routes through the example **card**'s
  runbook. In `frontend/src/lib/flows/guard.ts` replace `{ kind: 'example' }` with
  `{ kind: 'runbook'; runbook: Runbook }`; in `frontend/src/routes/+page.svelte` add the
  `perform()` case calling `openRunbookNow(runbook)` (the shape of `openExampleNow`, lines
  318-330): refusal → the editor notice with the platform's words, success → navigate to
  `flowHref(id)` and set `galleryDismissed`. Wire `RunbookGallery`'s `runbook-card-use` to
  `guarded({ kind: 'runbook'; runbook })`. T011 and T012 pass.

**Checkpoint**: the judge's path — click, see a real graph, run — works end to end (SC-002).

---

## Phase 5: User Story 3 — Cards tell the truth about the runbook (Priority: P2)

**Goal**: steps and destructive content marked on the card, cadence lines, and a data-derived
runnability verdict with a reason — an unusable card is never clickable-into-a-dead-end
(FR-004, FR-005, FR-007).

**Independent test**: with `iris-target` absent (routed empty targets list), *Cross-server
nightly* shows its graph but its Use is disabled with the reason naming the target; destructive
steps are marked on the weekly-window card; cadence lines show where declared.

### Tests first

- [X] T014 [P] [US3] Unit tests, failing first: `frontend/src/lib/flows/runbookCards.test.ts` per
  [data-model §2](data-model.md) — all-available types + targets present →
  `{ kind: 'runnable' }`; an unavailable type → `{ kind: 'unavailable' }` with the reason naming
  the type; a step's `target` missing from the list → the reason names the target; destructive
  flags from the registry; cadence shown iff declared; labels from registry labels.
- [X] T015 [P] [US3] Playwright first, failing, appended to
  `frontend/tests/us31-runbook-gallery.spec.ts`: (a) route `GET **/csp/sentai/api/v1/targets`
  with `[]` → the cross-server card's `runbook-card-use` is disabled and
  `runbook-card-reason` names `iris-target` (the retired `us20` unavailable guarantee, FR-007);
  (b) the weekly-window card marks *Switch journal* / *Purge task history* as destructive
  (FR-005); (c) cadence lines: nightly sweep "nightly", certificate watch "daily" (FR-004).

### Implementation

- [X] T016 [US3] Implement `frontend/src/lib/flows/runbookCards.ts` (pure:
  `runbookCards(runbooks, registry, targets)` → card view models with the `Availability` union)
  and wire it into `frontend/src/lib/flows/RunbookGallery.svelte`: unavailable ⇒ disabled
  `runbook-card-use` + `runbook-card-reason`; destructive accent via `MiniGraph.svelte`'s flags;
  the gallery fetches targets once per show through the existing `api.listTargets()`
  (`frontend/src/lib/api/client.ts:332`) passed in from the page — never a module-level cache
  (Constitution III). T014 and T015 pass.

**Checkpoint**: every card is honest; nothing runnable-looking leads to a dead end.

---

## Phase 6: User Story 4 — The gallery fits in without displacing anything (Priority: P2)

**Goal**: the guard, authoring, the *Getting started* auto-open, the tour and the shared demo
account all behave exactly as their specs define, with the gallery present (FR-008, FR-012,
FR-015, FR-016; spec 021 US3's invitation expectation superseded here).

**Independent test**: dirty + Use asks (T012 proof, re-run); a fresh profile auto-opens the guide
with the gallery beneath; the tour's three marks anchor over the gallery and it remains after
*Done*; keyboard-only traverses the gallery; both themes read.

### Tests first

- [X] T017 [P] [US4] Playwright first, failing, appended to
  `frontend/tests/us31-runbook-gallery.spec.ts`: (a) precedence — a routed refused flows-list →
  no `runbook-gallery` (the platform state wins, Constitution IV); sign-in expiry → no gallery
  over the overlay; (b) tour coexistence — with the gallery on screen, **Tour** → three marks
  anchored on palette/connection-surface/validate-run, gallery beneath and still there after
  *Done* (FR-015, the behavior the adapted `us30` scenario also pins); (c) fresh profile → the
  *Getting started* dialog still auto-opens once, gallery visible beneath it after closing
  (spec 010 FR-020, SC-004); (d) shared account — use a runbook, edit it, sign out and in → Use
  on the same card opens the same flow with the edits intact (scenario 4.5); (e) keyboard-only:
  Tab reaches every card's Use and *Start from scratch*, Enter activates; (f) both themes:
  contrast pass over the cards via the suite's `contrastFailures` helper.

### Implementation

- [X] T018 [US4] Close whatever T017's failing scenarios reveal — expected homes:
  the `showGallery` derivation's precedence in `frontend/src/routes/+page.svelte` (unreadable
  panel, session expiry, phase guards), focus order and labels in
  `frontend/src/lib/flows/RunbookGallery.svelte`, and card contrast via the design tokens in
  `frontend/src/lib/design/` (generated — edit `specs/002-canvas-ui/contracts/tokens.json` only
  if a token is genuinely missing). T017 passes green.

**Checkpoint**: SC-004's zero-regression stance is demonstrated, not asserted.

---

## Phase 7: User Story 5 — One ready-made path, not two (Priority: P3)

**Goal**: the *Getting started* dialog and *Open flow…* offer **Browse runbooks** and land on the
gallery; the lone example retires into the seventh card; no path offers a single example anymore
(FR-013).

**Independent test**: from the guide, step 2's button lands on the gallery; same from
*Open flow…*; a search for "Open example flow" in the served bundle finds nothing; the example
card is present and works.

### Tests first

- [X] T019 [P] [US5] Playwright first, failing: update the step-2 scenario of
  `frontend/tests/us21-getting-started.spec.ts` (lines 150-168) and add to
  `frontend/tests/us31-runbook-gallery.spec.ts` — (a) guide step 2 (**Browse runbooks**) →
  gallery; (b) *Open flow…* → **Browse runbooks** → gallery; (c) no "Open example flow" text
  anywhere on the Flows screen; (d) the example card is the seventh `runbook-card` and its Use
  opens `Example: storage health check` (FR-013).

### Implementation

- [X] T020 [US5] Rewire the entries: `frontend/src/lib/guide/steps.ts` step 2 — title
  "Open a runbook", body rewritten for the gallery (e.g. "Browse runbooks opens a gallery of
  ready-made flows…"), `action: 'browse-runbooks'`; `frontend/src/lib/guide/GettingStartedDialog.svelte`
  (line 22) and `frontend/src/lib/flows/OpenFlowDialog.svelte` (line 81): the button becomes
  **Browse runbooks** calling a new page handler `openRunbooksNow()` in
  `frontend/src/routes/+page.svelte` — guard when dirty (`{ kind: 'new' }`), then
  `newFlowNow()`-equivalent landing on the empty canvas with `galleryDismissed` reset so the
  gallery is what shows (FR-013); remove the now-unused `showExample`/`onexample` props from
  both dialogs and their call sites. T019 passes; `us21` (updated in T019) stays green.

**Checkpoint**: one ready-made path; the spec's supersession list is fully realized.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T021 Full-suite validation, recording results in
  `specs/022-runbook-gallery/evidence/README.md`: `cd frontend && npm test && npm run check &&
  npm run build`; `bash scripts/publish-canvas.sh`; `npx playwright test` (full — zero failures
  beyond the pre-existing shared-stack set); `zpm "load /home/irisowner/dev"` +
  `zpm "test sentai-task -only"` → 269 total, `All PASSED`. Any red: fix before this closes.
- [X] T022 [P] Record the `us20` → `us31` guarantee mapping table (plan D-9) and the SC-001…SC-004
  evidence rows in `specs/022-runbook-gallery/evidence/README.md`; run
  `scripts/check-spec-status.sh` — `Status` must match this file (nothing checked beyond this
  point, or all checked, per the spec-status rules).
- [ ] T023 [external] SC-005 usability spot-check — 3 of 3 hands-off first-time operators open a
  runbook from the public demo's gallery and start a run, per [quickstart.md](quickstart.md)
  (counts/notes only into evidence, no personal data). Needs people and the published demo;
  owned by the team, due before voting ends 2026-10-04. It never blocks `Implemented`; the spec's
  `**Status note**` says who owns it.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no dependencies — start immediately.
- **Phase 2 (Foundational)**: after Setup; **blocks all stories** (every card renders this data).
- **US1 (Phase 3)**: after Phase 2. No story dependencies.
- **US2 (Phase 4)**: after US1 (cards must exist to be clicked).
- **US3 (Phase 5)**: after US1 (verdicts decorate the cards); independent of US2.
- **US4 (Phase 6)**: after US2 (guard/Use behavior must exist to be proven); benefits from US3's
  verdicts for the disabled-card cases.
- **US5 (Phase 7)**: after US1 (entries land on the gallery) and US2 (`useRunbook` plumbing).
- **Phase 8 (Polish)**: after all desired stories.

### Within Each User Story

- Tests first and failing (Constitution V): T006/T007 → T008/T009/T010; T011/T012 → T013;
  T014/T015 → T016; T017 → T018; T019 → T020.
- Data before the modules that render it (Phase 2 → Phase 3+).
- Every checkpoint leaves the whole suite green — the suite-adaptation tasks ride **with** the
  change that breaks the old assertions (T007 with the gallery, T019 with the rewiring).

### Parallel Opportunities

- T002 ∥ T003 (different files) once the branch exists; T003 ∥ T004 are the same TDD pair —
  write tests and implementation together, they are one task pair per file.
- T005 (IRIS) runs parallel to any frontend task in Phase 3 — different codebases, different loops.
- T006 ∥ T007 ∥ (T008 preparation): unit and e2e tests are different files.
- T011 ∥ T012 ∥ T014 ∥ T015 once their stories unblock: all test files, no shared state.
- T017 ∥ T019 cannot (both append to `us31`) — run sequentially.
- With a team: US1 → (US2 ∥ US3) → (US4 ∥ US5) is the widest safe split.

---

## Implementation Strategy

### MVP First

1. Phase 1 + Phase 2 (branch, baselines, data + fixture sync).
2. Phase 3 (US1): the gallery replaces the empty canvas — the demo value on its own.
3. **STOP and VALIDATE**: `npm test`, `npm run check`, `us31` + adapted `us21`/`us30` green.
4. The demo-ready bar is **US1 + US2** (SC-002's click-to-running-flow promise) — publish and
   show the judge the five-second path once Phase 4 closes.

### Incremental Delivery

1. Foundation (data) → 2. Gallery (US1) → 3. Use (US2) → demo-ready → 4. Honesty (US3) →
5. Coexistence proof (US4) → 6. One path (US5) → 7. Polish + the external spot-check (Phase 8).

### Parallel Team Strategy

- One developer per story once US1 lands: US2 and US3 in parallel; US4 and US5 in parallel after.
- The IRIS fixture test (T005) is isolated enough for a second loop (its own load + test cycle).

---

## Notes

- [P] = different files, no dependency on incomplete tasks; [US n] maps to spec.md's stories.
- Publish before every e2e session: the tests drive the container's baked bundle, not a dev server.
- Do not hand-edit `module.xml`'s `<Version>` (CI bumps it) or the SPECKIT block in AGENTS.md.
- `frontend/src/lib/design/tokens.{css,ts}` are generated — never edit them directly.
- If a fixture comparison fails, the rule is fix-the-definitions-or-the-fixture **together** in
  one change, never delete the test ([research R-2](research.md)).
