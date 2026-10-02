# Implementation Plan: Runbook Gallery — Named Ready-Made Flows Instead of the Empty Canvas

**Branch**: `feat/spec022` (feature dir `022-runbook-gallery`; no branch exists yet — no git hook is installed) | **Date**: 2026-10-01 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (1 answered clarification, 17 FRs, 5 SCs). Frontend-only in product
terms: the runbook catalog is bundled data, cards are pure view models, and **Use** reuses the
create-or-open pattern the example flow proved (spec 010 FR-017) — so there is **no new wire
contract, no backend product change, and no demo-setup change** (FR-014). One IRIS **test method**
is added to complete the fixture-sync pattern ([research R-2](research.md)). The UI surface the
tests enforce is [contracts/runbook-gallery.md](contracts/runbook-gallery.md).

## Summary

The empty canvas becomes a gallery of seven cards (the six runbooks the spec names + the example
flow as a card, FR-002/FR-013), each with its mini-graph drawn from the shipped definition and a
**Use** control:

1. **The gallery state (FR-001…FR-005, FR-012)**. `RunbookGallery.svelte` replaces the invitation
   at its mount, shown whenever the Flows canvas is empty with no flow open — including on
   instances with saved flows, which is the demo's exact case (the old `noFlows` term is dropped).
   Cards come from bundled data (`runbooks.ts`); the pure view model (`runbookCards.ts`) computes
   each verdict from the registry + the targets list; the mini-graph (`miniGraph.ts` +
   `MiniGraph.svelte`) is an SVG scaled from the definition's `canvasGeometry` — nodes labelled
   with registry labels, destructive steps accented, suggested cadence as text.
2. **Use (FR-006…FR-010)**. `useRunbook` generalizes `openExample`: find by the runbook's
   `flowName` → open; else create through the ordinary `POST /flows` with the operator's own
   sign-in; a 409 re-lists. Refusals surface verbatim. The guard's `'example'` kind becomes
   `{ kind: 'runbook'; runbook }`, so a dirty canvas asks first (FR-008).
3. **One ready-made path (FR-013, FR-015, FR-016)**. The guide's and *Open flow…*'s buttons
   become **Browse runbooks** landing on the gallery; the lone example retires into the seventh
   card. The tour anchors over the gallery unchanged; keyboard and theming hold.

Nothing changes about validation, dispatch, the run engine, the scheduler, the demo setup or its
daily reset.

## Technical Context

**Language/Version**: TypeScript 5.9, Svelte 5 (runes), SvelteKit 2 (`adapter-static`, one
prerendered page, `ssr = false`), as in specs 002/007/009/010/021. The backend (ObjectScript on
IRIS 2026.2) gains **no product change** — one `%UnitTest` method only ([research R-2](research.md)).

**Primary Dependencies**: none new. `@xyflow/svelte` stays on the editable canvas only; cards draw
their own SVG ([research R-5](research.md)).

**Storage**: **none** (the gallery owns no state; `galleryDismissed` is session `$state`, like the
`invitationDismissed` it replaces). No `localStorage`, no server record of used runbooks — the
platform's name index is the only memory (FR-006, Constitution III).

**Testing**:
- vitest on the pure modules: `runbooks.ts` (data invariants + fixture equality),
  `runbookCards.ts` (verdicts), `miniGraph.ts` (geometry), `useRunbook` (create-or-open machine),
  `guard.test.ts` (the new kind).
- Playwright `tests/us31-runbook-gallery.spec.ts` against the compose stack (publish first),
  evidence into `specs/022-runbook-gallery/evidence/`; `us20` retires into it, `us21`/`us30`
  adapt their invitation scenarios ([research R-9](research.md)).
- IRIS: `zpm "test sentai-task -only"` gains `DemoTest.TestWeeklyWindowMatchesFixture` (and keeps
  the two existing fixture comparisons).

**Target Platform**: Chromium, Firefox and WebKit through Playwright, as the existing suite; the
static app is served by IRIS at `/csp/sentai/`.

**Project Type**: web application (frontend slice + one backend test).

**Performance Goals**: SC-002's promise — from the gallery to an open flow in ≤ 2 actions and
~5 s. The gallery renders from already-loaded data (registry) plus one `GET /targets`; the cards
are static SVG. No request is made while merely viewing.

**Constraints**:
- No new endpoint, no wire change, no demo-setup change (FR-014) — the fixture test is test-only.
- The curated set is exactly seven cards; more enter only through the ordinary change process
  (FR-002, Q1 answer A).
- All gallery text in English (FR-017); **Use** is the label for the input's *Usar*.
- The top bar is untouched (the gallery is in-canvas), so the 1440 px fit check is not at risk.
- Voting-week budget: the minimal gallery (cards + Use + guard) is increment 1–2 and must land
  first; entry-point rewiring and suite adaptation follow.

**Scale/Scope**: 1 new feature folder slice in `lib/flows` (4 new modules + 2 components), 4
touched files, 3 adapted e2e specs (1 retired, 2 edited), 1 new IRIS test method; ~30 unit cases,
~14 e2e scenarios. `EmptyCanvasInvitation.svelte` and `us20-example-flow.spec.ts` are deleted.

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 (see end). Every row passes; no
Complexity Tracking entries.*

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | Components (`RunbookGallery.svelte`, `MiniGraph.svelte`) → pure modules (`runbooks.ts` data, `runbookCards.ts` verdicts, `miniGraph.ts` geometry, `useRunbook` io via the injected `api` interface) → `lib/api/client.ts` (the only HTTP edge, unchanged). No component calls `fetch`; `useRunbook` takes the same `ExampleApi`-shaped interface `openExample` takes today. | ✅ |
| **II Closed Capability Set** | Runbooks are fixed, typed data in the codebase composed only of catalog step types with declared parameters filled (FR-011); the gallery is not runtime-extensible; **Use** creates through the ordinary validated flow path. Nothing an operator types is evaluated anywhere on the gallery's path. | ✅ |
| **III Delegated Authorization** | Every create uses the operator's own sign-in; the name index — not a local record — decides "already exists"; refusals surface verbatim (FR-009). The card verdict is derived from catalog/target **data** (step availability, target existence), never a cached permission outcome; permission is decided by the platform at create/run time as today. The targets read is refetched per gallery show — nothing cached across requests. | ✅ |
| **IV Errors as Values** | `useRunbook` returns `ApiResult`, refusal included — the page maps it to the editor notice, never a throw; an unavailable card is a value (`{ kind: 'unavailable'; reason }`), rendered as a disabled control with its reason (FR-007); the gallery never renders over a platform state (same precedence as the invitation it replaces). | ✅ |
| **V Verifiable Increments** | Three increments, each user-observable with its failing e2e first (see *Increments*). None is a layer ticket: 1 delivers a judge-visible gallery; 2 delivers the click-to-running-flow promise; 3 delivers the one-path coexistence a returning operator feels. | ✅ |
| **VI Technology Agnosticism** | Technology appears only here and in [research.md](research.md); the spec and constitution are untouched. | ✅ |
| SOLID / SoC | One reason to change per module: curated content (`runbooks.ts`), verdicts (`runbookCards.ts`), geometry (`miniGraph.ts`), create-or-open io (`useRunbook` in `runbooks.ts`, mirroring `example.ts`'s proven shape), presentation (`RunbookGallery.svelte`, `MiniGraph.svelte`), page wiring (`+page.svelte`). | ✅ |
| TDD | Every task starts with the failing test: vitest for data invariants, verdicts, geometry and the create-or-open machine; Playwright for observable gallery behaviour (see *Testing Strategy*). | ✅ |
| YAGNI | No runbook-authoring UI, no server catalog, no search/filter over seven cards, no copy-for-me naming, no schedule creation from a cadence line, no minimap library — each considered and rejected ([research R-1, R-3, R-5, R-8](research.md)). | ✅ |
| Reproducibility | No new toolchain: `docker compose up`, `npm ci`, `publish-canvas.sh`, `npx playwright test`, `zpm "load"` + `zpm "test"` as today. | ✅ |

## Decisions

- **D-1 Bundled data, not a server catalog ([research R-1](research.md)).** The seven runbooks
  ship as typed data in `frontend/src/lib/flows/runbooks.ts` (`Runbook` of
  [data-model §1](data-model.md): `title`, `purpose`, optional `suggestedCadence`, `flowName`,
  `definition`). `flowName` is the identity: for *Cross-server nightly* it is the seeded
  showcase's name (`"Showcase: nightly checks across servers"`), so the demo's existing
  distributed flow is what opens; the `title` is what the card displays. The example card reuses
  `exampleDefinition()` (`example.ts:14-36`) — its fixture test stays.
- **D-2 Two-sided fixture sync for the three shared definitions ([research R-2](research.md)).**
  vitest compares the bundled example/weekly-window/cross-server definitions to
  `tests/fixtures/{example-flow,weekly-window-flow,showcase-flow}.json`;
  `DemoTest.TestWeeklyWindowMatchesFixture` completes the ObjectScript side (the example and
  showcase comparisons already exist, `DemoTest.cls:60-75`). Editing any of the three definitions
  means editing its fixture in the same change — both suites fail otherwise.
- **D-3 Use = create-or-open by `flowName` ([research R-3](research.md)).** `useRunbook(api,
  runbook)` generalizes `openExample` (`example.ts:61-75`) verbatim in mechanics: list → find
  (case-insensitive) → open; else create; 409 → re-list. `openExample` folds into it and the
  `'example'` guard kind retires.
- **D-4 Card verdicts ([research R-4](research.md), [data-model §2](data-model.md)).** Pure
  `runbookCards(runbook, registry, targets)`: runnable iff all step types are declared+available
  and every step's `target` exists in the targets list (one `GET /targets` per gallery show,
  through the existing client). Unavailable ⇒ disabled Use + `runbook-card-reason`. Destructive
  steps are flagged from the registry (`document.ts:6-14`). No permission is ever pre-guessed —
  the platform refuses at create/run time and its words pass through (FR-009).
- **D-5 The mini-graph ([research R-5](research.md), [data-model §3](data-model.md)).** Pure
  `miniGraph(definition, registry)` scales `canvasGeometry.nodes` into a fixed card viewBox and
  computes edge segments; `MiniGraph.svelte` renders the SVG (registry labels, destructive
  accent, arrowheads). No `@xyflow` in cards; no layout algorithm (all shipped definitions carry
  geometry).
- **D-6 The gallery state ([research R-6](research.md), [data-model §5](data-model.md)).**
  `showGallery = unreadable === null && editor.id === null && editor.steps.length === 0 &&
  !galleryDismissed`, replacing `showInvitation` (`+page.svelte:236`) at the same mount
  (`:556-561`). The `noFlows` boot fact (`:77`, `:232`) retires with the invitation. Precedence
  (unreadable panel, refusals, sign-in overlay) is untouched.
- **D-7 The guard ([research R-7](research.md)).** `PendingSwitch`'s `{ kind: 'example' }`
  (`guard.ts:8`) becomes `{ kind: 'runbook'; runbook: Runbook }`; `perform()` gains
  `openRunbookNow` (the shape of `openExampleNow`, `+page.svelte:318-330`). A successful Use sets
  `galleryDismissed`. `guard.test.ts` enumerates the new kind; the dialog copy is unchanged.
- **D-8 Entry points ([research R-8](research.md)).** The guide's step 2
  (`steps.ts:17-20`, `GettingStartedDialog.svelte:22`) and the *Open flow…* dialog
  (`OpenFlowDialog.svelte:81`) get **Browse runbooks**, calling one page handler: guard when
  dirty → land on the empty canvas with `galleryDismissed` reset — the gallery is what an empty
  canvas shows (FR-013). The old "hide when unavailable" button rule retires with the lone
  example; honesty lives in the per-card verdicts (FR-005/FR-007).
- **D-9 Suite adaptation, owned 1:1 ([research R-9](research.md)).** `us20` retires; its
  guarantees move to `us31` (offered → card present; idempotent → same flow on re-Use; guard →
  asks over dirty; unavailable → disabled card with reason). `us21` adapts step 2, the
  "on first use" scenario and the invitation theming shot; `us30`'s single
  invitation-under-tour scenario asserts the gallery (FR-015).

## Project Structure

### Documentation (this feature)

```text
specs/022-runbook-gallery/
├── spec.md
├── plan.md                        # this file
├── research.md                    # R-1 … R-10 (findings, decisions, rejected alternatives)
├── data-model.md                  # Runbook, RunbookCard, MiniGraph, use machine, gallery state
├── contracts/runbook-gallery.md   # the UI contract: testids, entries, Use outcomes, fixture sync
├── quickstart.md                  # SC-001…SC-005 script + automated commands
├── checklists/requirements.md
└── tasks.md                      # /speckit-tasks (not created here)
```

### Source Code

```text
frontend/src/lib/flows/
├── runbooks.ts, runbooks.test.ts         # NEW — the 7 runbooks (data) + useRunbook (create-or-open)
├── runbookCards.ts, runbookCards.test.ts  # NEW — pure verdicts + card view model
├── miniGraph.ts, miniGraph.test.ts       # NEW — pure geometry for the card SVGs
├── RunbookGallery.svelte                 # NEW — the gallery region (cards, Start from scratch)
├── MiniGraph.svelte                      # NEW — one card's SVG
├── example.ts, example.test.ts           # TOUCH — definition stays (card reuses it); openExample folds into useRunbook
├── guard.ts, guard.test.ts               # TOUCH — 'example' kind → { kind: 'runbook'; runbook }
├── EmptyCanvasInvitation.svelte          # RETIRED (deleted)
├── OpenFlowDialog.svelte                  # TOUCH — Browse runbooks entry
frontend/src/lib/guide/
├── steps.ts                               # TOUCH — step 2 copy + action
├── GettingStartedDialog.svelte            # TOUCH — Browse runbooks button
frontend/src/routes/+page.svelte           # TOUCH — showGallery derivation, openRunbookNow, entry handler,
                                           #         guard perform case, galleryDismissed
tests/sentai/unittest/demo/DemoTest.cls    # TOUCH — TestWeeklyWindowMatchesFixture (test-only)
frontend/tests/
├── us31-runbook-gallery.spec.ts           # NEW — the gallery end to end
├── us20-example-flow.spec.ts               # RETIRED (guarantees moved 1:1 into us31)
├── us21-getting-started.spec.ts           # TOUCH — step 2, first-use scenario, theming shot
└── us30-first-time-tour.spec.ts           # TOUCH — gallery-under-tour scenario
```

**Structure decision**: the existing SvelteKit app, one new feature slice inside `lib/flows`
(the gallery's siblings — `example.ts`, `guard.ts`, `OpenFlowDialog.svelte` — are exactly the
modules it extends). `src/sentai/**` product code is untouched; the single IRIS edit is a test
method. `frontend/media/showcase.media.ts` (spec 014's recorder) reads the showcase fixture
directly and needs nothing.

## Increments (Constitution V)

| # | Increment (observable) | Depends on | First failing test |
|---|---|---|---|
| 1 | The empty canvas is the gallery: seven cards with mini-graphs, purposes, cadence lines, destructive marks and verdicts; *Start from scratch*; keyboard-operable; shown also with saved flows | — | `us31`: sign in → Flows (no flow open) → `runbook-gallery` visible with 7 `runbook-card`s; each `runbook-card-graph` shows the definition's node/edge counts; flows exist (route GET /flows with a list) and the gallery still shows |
| 2 | Use works end to end: a card click opens/creates the flow, idempotent, guarded over dirty, refusals verbatim | 1 | `us31`: Use on *Weekly maintenance window* → flow open, graph matches the card; Use again → same id; dirty → Save/Discard/Cancel first; cross-server card disabled with reason when `iris-target` is absent |
| 3 | One ready-made path and clean coexistence: **Browse runbooks** from the guide and *Open flow…* lands on the gallery; tour anchors over the gallery; us20 retired, us21/us30 adapted | 1, 2 | `us31`: guide step 2 → gallery; *Open flow…* → gallery; `us30` (edited): tour over gallery, marks anchored, gallery beneath after *Done* |

## Testing Strategy

**TDD**: the failing test first, for the reason the task fixes. Unit for pure logic, Playwright
for observable behaviour, one IRIS method for fixture sync (Constitution V).

**Unit (vitest)**, ~30 cases:
- `runbooks.test.ts`: exactly 7 runbooks; unique non-empty `flowName`s; `definition.name ===
  flowName`; every step type declared+available in a reference registry; every declared parameter
  filled; every definition carries `canvasGeometry`; the three fixture-backed definitions equal
  `example-flow.json` / `weekly-window-flow.json` / `showcase-flow.json` (name, content,
  geometry — the `example.test.ts:74-76` comparison pattern); cross-server `flowName` is the
  showcase's seeded name; English titles.
- `runbookCards.test.ts`: all-available + targets present → runnable; an unavailable type →
  disabled + reason names it; a step's target missing → disabled + reason names the target;
  destructive flags surface; cadence shown iff declared; steps labelled with registry labels.
- `miniGraph.test.ts`: nodes scaled into the viewBox preserving relative layout; edge segments
  connect source/target borders; destructive nodes flagged; a definition's node/edge counts are
  what the SVG exposes.
- `useRunbook` (in `runbooks.test.ts`): existing flow by name → its id, no create; missing →
  create called once with the definition; 409 → re-list → id; refused list/create → the refusal
  passes through unchanged.
- `guard.test.ts`: the `{ kind: 'runbook' }` kind decides like the others.

**End-to-end (Playwright, compose stack)**, ~14 scenarios in `us31-runbook-gallery.spec.ts`
(owning `us20`'s retired guarantees):
- gallery on the empty canvas with 7 cards; shown with saved flows (route `GET …/flows` with a
  list — proving the `noFlows` independence, FR-001/SC-001);
- per-card mini-graph counts equal the definition's steps/edges; cadence lines; destructive marks
  (FR-003, FR-005);
- Use → flow open in ≤2 actions; validate passes; run completes (the judge's path, FR-006,
  SC-002);
- idempotence: Use twice → one flow (FR-006, the retired `us20` guarantee);
- guard: dirty canvas + Use → Save/Discard/Cancel; Cancel keeps the editor (FR-008, the retired
  `us20` guarantee);
- unavailable card: `iris-target` missing (route `GET …/targets` with `[]`) → Use disabled +
  reason (FR-007, the retired `us20` guarantee);
- refusals verbatim: route `POST …/flows` 403 with a problem body → the platform's words surface
  (FR-009);
- *Start from scratch* → blank canvas, palette usable (FR-012);
- entry points: guide step 2 and *Open flow…* → gallery (FR-013); no "Open example flow" remains
  anywhere;
- keyboard-only: Tab reaches every card's Use and *Start from scratch*; announced region
  "Runbooks" (FR-016);
- theming: both themes read on cards, contrast pass (FR-016, house pattern);
- tour coexistence: Tour over the gallery, three marks anchored, gallery beneath after *Done*
  (FR-015, edits `us30`'s scenario);
- `us21` (edited): guide auto-open unchanged; step 2 opens the gallery; first-use scenario shows
  the gallery under the guide; theming shot of the gallery.

**Commands**: `cd frontend && npm test && npm run check && npm run build`; `bash
scripts/publish-canvas.sh`; `npx playwright test tests/us31*` then the full `npx playwright test`;
`zpm "load /home/irisowner/dev"` + `zpm "test sentai-task -only"` for the DemoTest method.

### Success criteria: automated vs manual

| SC | Automated | Manual (quickstart) |
|---|---|---|
| SC-001 gallery is the empty canvas, flows or not | ✅ `us31` (visibility, 7 cards, routed flows list) | ✅ timed ~5 s check on the demo |
| SC-002 ≤2 actions / ~5 s to a running flow | ✅ `us31` (Use → open; validate → run) | ✅ the click-to-run script, timed |
| SC-003 validation parity + refusals verbatim | ✅ `us31` (validate 0 errors; routed 403 surfaces) + vitest (`useRunbook` refusal passthrough) | ✅ watch one refusal surface as-is |
| SC-004 0 regressions (guard, guide, tour, hint) | ✅ full suite (`us21`/`us30` adapted, `us20` retired into `us31`, tour marks anchored) | ✅ fresh-profile sweep (quickstart) |
| SC-005 3 of 3 hands-off first-time runs | ⚠ e2e proves the cards carry the content; completion needs people | ✅ **manual**: 3 operators on the public demo, counts only into evidence |

## Risks

| Risk | Mitigation |
|---|---|
| A card's bundled definition drifts from a seeded flow (the demo would draw one graph and open another) | Two-sided fixture comparison fails both suites on drift ([research R-2](research.md)); the three fixtures are named in [data-model §7](data-model.md). |
| The gallery shows over a platform state (refusal, unreachable) | Same derivation shape and precedence as the invitation it replaces; `us31` proves the unreadable panel still wins (Constitution IV). |
| The daily demo reset deletes a used *Weekly maintenance window* (`IsSeeded` covers only two names, `Demo.cls:214-218`) | Nothing to fix — the card is open-or-create: after a reset, Use re-creates it from the definition; reset behaviour itself is untouched (FR-014, spec edge case). |
| The card verdict is mistaken for a permission decision (Constitution III) | The verdict derives only from catalog/target data and is recomputed per show; permission stays with the platform at create/run time; refusals surface verbatim (`us31`'s routed 403). |
| Scope creep past the voting-week budget (more runbooks, authoring UI, search) | FR-002 is exactly seven cards (Q1 answer A); the YAGNI row lists the rejected extensions. |
| `us21`/`us30` edits break unrelated scenarios | The edits are confined to the invitation-touching scenarios (mapping in D-9); the full e2e run is the gate before `Implemented`. |

## Complexity Tracking

No constitutional violations; nothing to justify.

## Post-Design Constitution Re-check

Re-evaluated after writing [research.md](research.md), [data-model.md](data-model.md) and
[contracts/runbook-gallery.md](contracts/runbook-gallery.md):

- **I**: cards/geometry/verdicts are pure modules behind components; the only HTTP is the
  existing client through an injected interface — no cross-layer shortcut.
- **II**: seven fixed data definitions of declared types; the gallery is not runtime-extensible.
- **III**: operator's own credential on every create; name index is the only memory; verdicts
  are data, never cached permissions; refusals verbatim.
- **IV**: create-or-open and unavailability are values; the gallery never masks a platform state.
- **V**: three observable increments, failing e2e first; the one IRIS test rides the same
  fixture-contract increment as the data it guards.
- **VI**: technology appears only here and in research.

**Gate: PASS.**
