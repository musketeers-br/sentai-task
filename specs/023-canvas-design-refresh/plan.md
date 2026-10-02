# Implementation Plan: Canvas Design Refresh — Flow Chrome, Catalog Detail and Overview Attention

**Branch**: `023-canvas-design-refresh` | **Date**: 2026-10-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/023-canvas-design-refresh/spec.md`

**Base**: `origin/master` at `ab637c0` (specs 018 and 019 merged). Re-based after `/speckit-analyze`
on 2026-10-01; the first draft was written on `feat/spec020`, before 019 landed.

## Summary

Turn the Claude Design proposal (board section 05) into three shippable slices of the SvelteKit
canvas. Research found much of it already built by specs 007, 010, 012 and 019 (research R-1), so the
plan is a set of deltas:

- **US1 flow chrome**: split `TopBar.svelte` into a global bar (identical on every screen) and a
  new `FlowBar.svelte`. Disabled-action reasons become visible text. The empty canvas gets a real
  empty state (the template is offered on any instance). The inspector gets a "Nothing selected"
  pane, the status bar gets snap and zoom, and the palette collapses long categories and the
  types not supported in v1.
- **US2 catalog**: one additive backend change, `counts` and `unclassifiedOnly` on
  `GET /catalog/tasks` plus the task `description` (R-2, R-3). The canvas adds count badges, the
  unclassified filter, "updated N s ago" and a footer. The detail gets the destructive reason
  (R-4), the "created outside SentaiTask" mark, "Add to a flow" (R-6) and a Suspend/Resume toggle
  with a simple confirmation over the existing spec 007 call (R-7).
- **US3 overview attention**: extend spec 019's Overview with an unread summary, Needs attention
  and Next 24 hours, from the catalog read (with US2's `counts`) and 019's summary cards (R-8,
  R-13). 019's cards, reading view, *Run report* and *Schedule this check* are untouched (R-9).

## Technical Context

**Language/Version**: TypeScript 5 / Svelte 5 (runes) on SvelteKit (static adapter, served by
IRIS at `/csp/sentai/`); ObjectScript on IRIS 2026.2 for the one catalog API change.

**Primary Dependencies**: `@xyflow/svelte` (canvas, `Controls`, `MiniMap`) — existing; new dev
dependency `@axe-core/playwright` (R-12). No new runtime dependency.

**Storage**: none new. The catalog `counts` are computed per request.

**Testing**: `vitest` for every new pure module (`flowbar`, `consequence`, palette collapse,
catalog summary/detail, overview `attention`), written first; `svelte-check`; Playwright e2e
against the published bundle on :52773, with three new specs (us30–us32), the renamed flow controls
behind one `flowAction()` helper, and `us29-overview.spec.ts` (spec 019) passing unchanged; `%UnitTest` through `zpm "test sentai-task -only"` for `counts`,
`unclassifiedOnly` and `description` (`tests/sentai/unittest/catalog/`).

**Target Platform**: desktop browsers from 1280 px wide (spec assumption), 1440 × 900 for evidence;
dark and light themes.

**Project Type**: web application. ObjectScript REST backend (`src/sentai`) plus the SvelteKit
canvas (`frontend/`).

**Performance Goals**: the two new Overview bands visible within 3 s (SC-007). Measured: catalog
read 0.10 s (16 tasks), spec 018 summary ≈ 0.57 s; both run concurrently and each band renders as
soon as its own read answers.

**Constraints**: components never call `fetch`; view models are pure (AGENTS layering); screen
state is a tagged union; colours, sizes and radii come only from `tokens.json`; no value the API
did not send is shown (spec 007 `Value<T>`); every refusal is passed through verbatim.

**Scale/Scope**: about 13 changed and 8 new frontend files, 3 backend classes, 3 new e2e specs.
Dev instance: 16 tasks, 2 suspended, 2 destructive, 12 unclassified; spec 019's 11 cards, unchanged.

## Constitution Check

*GATE: checked before Phase 0 and re-checked after Phase 1 design.*

| Principle | How this plan satisfies it | Pre | Post |
|---|---|---|---|
| I. Layered architecture | Components → `lib/<domain>/*.ts` view models → `lib/api/client.ts`. `FlowBar`, the new Overview bands and the catalog additions read only view models; `attention.ts` reads spec 019's `AreaCardView` model without redefining it. The backend change stays inside `sentai.catalog` (`TaskService`, `TaskFilter`, `TaskShape`); `Dispatcher` only passes the new parameter. | ✅ | ✅ |
| II. Closed capability set | No capability is added. "Classify" is a filter plus an explanation (FR-019). "Add to a flow" resolves a step type only by matching the catalog's `className` (R-6). Spec 019's reports and *Schedule this check* (018's closed area list) are unchanged. | ✅ | ✅ |
| III. Delegated authorization | Suspend, catalog and overview reads all use the operator's token. The toggle is never hidden because a refusal is predicted, and refusals are shown verbatim. The board's fixed "%Admin_Task:USE" privilege is not shown (R-3), because it would state an authorization outcome. | ✅ | ✅ |
| IV. Errors as values | Each new Overview band is `Band<T>` = loading, ready or unread. An unread read is a value carried into the top summary, never `ready([])` (data-model §6). Missing `counts` from an older API is `unavailable`, never 0. The suspend state machine stays a reducer. | ✅ | ✅ |
| V. Verifiable increments | Three stories, each shippable alone, each with its e2e spec and vitest first. US2's backend change ships inside US2 with its catalog UI, not as a separate "API task". US3 declares its dependency on US2's `counts` (T026). | ✅ | ✅ |
| VI. Technology agnosticism | Technology is chosen here, not in the spec. The spec names behaviour only. | ✅ | ✅ |

**Engineering standards.** *SoC*: the flow bar and the global bar change for different reasons, so
they are separate components. The destructive consequence text has one source (R-4). *YAGNI*: no
template gallery, no rebuild of spec 019's screen, no overview caching or polling (Refresh only),
no new catalog route. *TDD*: see
Testing.

No violations; Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/023-canvas-design-refresh/
├── spec.md
├── plan.md              # this file
├── research.md          # R-1..R-13
├── data-model.md        # catalog delta + canvas view models
├── quickstart.md        # end-to-end validation
├── contracts/
│   └── api-delta.md     # catalog counts / unclassifiedOnly / description; canvas addresses
├── checklists/
│   └── requirements.md
├── evidence/            # PNG/JSON + README table (board ↔ screenshot)
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
src/sentai/catalog/
├── TaskService.cls        # CHANGED  List: counts over all tasks; unclassifiedOnly passed through
├── TaskFilter.cls         # CHANGED  Validate/Matches + unclassifiedOnly
└── TaskShape.cls          # CHANGED  description from the single read
src/sentai/rest/Dispatcher.cls   # CHANGED  reads unclassifiedOnly from the query string
tests/sentai/unittest/catalog/
├── TaskFilterTest.cls     # CHANGED  unclassifiedOnly valid/invalid/AND
└── TaskReadTest.cls       # CHANGED  counts unaffected by filters; description verbatim/absent

frontend/src/lib/
├── shell/
│   ├── TopBar.svelte      # CHANGED  global only: mark, tabs (019's Overview first), theme, Help, user, Sign out; 019's width squeezes reverted
│   └── StatusBar.svelte   # CHANGED  formatCanvasStatus (snap, zoom)
├── flow/
│   ├── FlowBar.svelte     # NEW      name, save state, Open…/Save/Validate/Run now/Schedule/⋯, reasons
│   ├── flowbar.ts(+test)  # NEW      FlowBarState (data-model §2)
│   ├── consequence.ts(+test) # NEW   moved from Inspector.svelte (R-4)
│   └── document.ts(+test) # CHANGED  formatCanvasStatus
├── flows/EmptyCanvasInvitation.svelte → EmptyCanvas.svelte  # CHANGED  explanation, legend, template, import
├── inspector/Inspector.svelte   # CHANGED  "Nothing selected" pane with flow name + WQM category; imports consequence
├── palette/
│   ├── Palette.svelte     # CHANGED  counts, Show N more, unsupported group
│   └── search.ts(+test)   # CHANGED  collapseGroups (data-model §4)
├── catalog/
│   ├── catalog.ts(+test)  # CHANGED  counts, unclassifiedOnly, description, destructiveReason, outsideMark, stepFromTask, suspendToggle, confirming state
│   ├── CatalogScreen.svelte  # CHANGED  header age, count badges, unclassified control, footer, URL filters
│   └── CatalogDetail.svelte  # CHANGED  description, reason, outside mark, Add to a flow, toggle + Modal
├── overview/              # CHANGED (spec 019's; overview.ts, AreaCard, ReadingView untouched)
│   ├── attention.ts(+test) # NEW  attention items, scheduleSlots, unread summary (data-model §6)
│   ├── UnreadSummary.svelte, AttentionBand.svelte, ScheduleStrip.svelte  # NEW
│   └── OverviewScreen.svelte # CHANGED  catalog read beside the summary; bands above the cards
└── api/client.ts          # CHANGED  catalog counts/description/unclassifiedOnly
frontend/src/routes/+page.svelte   # CHANGED  FlowBar on Flows, addToFlow wiring, catalog read + URL filters for Overview
frontend/tests/
├── support.ts             # CHANGED  flowAction(page, action), expectNoSeriousA11y(page)
├── us30-flow-chrome.spec.ts       # NEW  US1
├── us31-catalog-attention.spec.ts # NEW  US2 (extends us9/us10 patterns; suspends a task it creates)
├── us32-overview-attention.spec.ts # NEW US3 (us29-overview.spec.ts must keep passing)
└── 16 specs using flow controls   # CHANGED  through flowAction() (tasks T005)
frontend/package.json      # CHANGED  devDependency @axe-core/playwright
specs/002-canvas-ui/contracts/openapi.yaml  # CHANGED  counts, description, unclassifiedOnly
README.md                  # CHANGED  catalog query parameter; Overview attention bands
```

**Structure Decision**: the existing two-codebase layout. Frontend work follows the current
domain folders under `frontend/src/lib/`; US3 extends spec 019's `overview/`. The backend change stays
in the existing `sentai.catalog` package and its flat test directory.

## Sequencing

1. **US1** has no dependency and ships first.
2. **US2** carries its backend change (catalog counts) together with the catalog UI that consumes
   it. It is independent of US1, except that "Import from the task catalog" (US1) is a navigation
   link that works on either catalog.
3. **US3** depends on US2's `counts` (T026) for the attention band; specs 018 and 019 are already
   on the base.

## Risks

- **Sixteen e2e specs locate the renamed flow controls.** Mitigation: Phase 2 moves them behind
  `flowAction()` while the suite is green; US1 changes that one helper.
- **Stale base.** 023 was drafted on `feat/spec020`; it now sits on master, and any file 019 changed
  (`TopBar.svelte`, `+page.svelte`, `support.ts`, `overview/*`) is edited from master's version.
- **Regressing spec 019.** `us29-overview.spec.ts` and 019's vitest run unchanged in every US3
  checkpoint.
- **Width.** The flow bar at the minimum width must not hide controls; "⋯" absorbs overflow, and
  the e2e spec checks it at 1280 and 1440.

## Complexity Tracking

None.
