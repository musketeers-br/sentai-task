# Tasks: Canvas Design Refresh — Flow Chrome, Catalog Detail and Overview Attention

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md). Visual reference: Claude Design board "SentaiTask", section 05
(boards *Proposed — flow chrome*, *Proposed — Task catalog*, *Proposed — Overview*). Base:
`origin/master` with specs 018 and 019 merged; spec 019's Overview is extended, never replaced.

**Tests**: REQUIRED (Constitution V, TDD). vitest for every pure module (`frontend/src/**/*.test.ts`),
written first and seen failing. Playwright e2e against the **published** bundle on :52773
(`bash scripts/publish-canvas.sh` before every e2e run). Backend `%UnitTest` via
`zpm "load /home/irisowner/dev"` then `zpm "test sentai-task -only"`, whole suite, no single-class run.

**Hard rules**:
- Components never call `fetch`; new logic goes in `lib/<domain>/*.ts` and is unit-tested there.
- Colours, sizes and radii only from `specs/002-canvas-ui/contracts/tokens.json` (then
  `npm run generate:tokens`); never hand-edit `src/lib/design/tokens.*`.
- A value the API did not send stays absent (`Value<T>`); a refusal is shown verbatim (HTTP status +
  platform message); a failed read is never rendered as 0, empty or "nominal".
- e2e suspends/resumes only a task the test creates (`sentai-e2e-023-*`), deleted in `finally`.
- No hand edit of a `Storage` block or of `module.xml` `<Version>`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an open task)
- **[external]**: needs a human session or an action outside the repository; never blocks `Implemented`
- **[Story]**: US1, US2, US3 as in spec.md

---

## Phase 1: Setup

- [X] T001 Create branch `023-canvas-design-refresh` from `origin/master` (≥ `ab637c0`, which has specs 018 and 019), copy `specs/023-canvas-design-refresh/` onto it, set `.specify/feature.json` to `{"feature_directory":"specs/023-canvas-design-refresh"}`, and re-check the research R-1 table against that base before T006.
- [X] T002 [P] Record the baseline in `specs/023-canvas-design-refresh/evidence/README.md`: backend `zpm "test"` total, `npm test` total, `npm run check` result, and the Playwright pass count on the current bundle (no credentials in the file).
- [X] T003 [P] Add `@axe-core/playwright` as a devDependency in `frontend/package.json` (`npm i -D @axe-core/playwright`, commit the lockfile) and add `expectNoSeriousA11y(page: Page, label: string)` to `frontend/tests/support.ts`: runs AxeBuilder on the page, fails listing every violation with impact `serious` or `critical`, writes the JSON result to `specs/023-canvas-design-refresh/evidence/a11y-<label>.json`.

---

## Phase 2: Foundational (blocking — renamed flow controls behind one helper)

**Purpose**: US1 renames the flow controls and collapses palette groups; 16 e2e specs locate those
controls by their current names and 12 locate palette entries by `data-step-type`. Move those
locators behind helpers now, while the suite is green, so US1 changes one file.
(Reaching Flows is already handled: `signIn()` uses `?view=flows` since spec 019.)

- [X] T004 Add `flowAction(page, action)` to `frontend/tests/support.ts`, with `action ∈ 'open'|'save'|'saveAs'|'new'|'validate'|'run'|'schedule'|'history'` returning today's control (`Open flow…`, `Save flow`, More → `Save as…`/`New flow`/`Run history`, `Validate flow`, `Run now`, `Schedule in Task Manager`) and opening the menu when the action lives in one. Also `paletteEntry(page, type)` (returns the entry, expanding its collapsed group or the unsupported group first when needed — a no-op today) and `expandPalette(page)` (opens every collapsed group, for specs that check a whole group).
- [X] T005 Replace direct locators of those controls with `flowAction` in `frontend/tests/`: us1-flow-composition, us2-inspector-validation, us3-schedule, us6-theming, us11-declared-steps, us13-management-theming, us16-remote-run, us17-save-as-and-new, us18-open-flow, us19-kept-sign-in, us20-example-flow, us21-getting-started, us25-run-history, us28-schedule, us29-overview, us29-security-inventory (`.spec.ts`; list from `grep -lE "Save flow|Validate flow|Schedule in Task Manager|'More'|Open flow…|New flow|Save as…|Run history"` on `master`). Palette entries located by `data-step-type` in us1, us11, us12, us17, us18, us19, us20, us21, us27, us29-security-inventory go through `paletteEntry`/`expandPalette` (us22/us23 search first, so they stay as they are). Full Playwright run on the current bundle: same pass count as T002. *(Done 2026-10-01 straight to the final helpers — `flowButton(page, action)`, `flowMoreButton(page)`, `paletteEntry`, `expandPalette` — together with T019, without the intermediate run on the old bundle; verified by the T020 runs.)*

**Checkpoint**: suite green, no behaviour changed; US1 and US2 can start in parallel.

---

## Phase 3: User Story 1 — The flow editor says what the flow is and what to do next (P1) 🎯 MVP

**Goal**: global bar identical on every screen; a flow bar with save state, actions and visible
disabled reasons; real empty state; "Nothing selected" inspector; snap/zoom in the status bar;
collapsed palette (FR-001, FR-003–FR-014).

**Independent test**: quickstart §2 at 1440 × 900 and 1280 × 800, dark and light.

### Tests first (US1)

- [X] T006 [P] [US1] Write `frontend/src/lib/flow/flowbar.test.ts` for `flowBarState(editor-like input)` (data-model §2): no steps → validate/run/schedule disabled with reason `"add a step to enable running"`; `scheduleBlocked` → run/schedule disabled with `"fix the validation errors in the status bar"`, validate enabled; validating → validate disabled, reason null; `id === null` → `{kind:'unsaved'}`; saved → `rev N · saved HH:MM` from `savedAt` "YYYY-MM-DD HH:MM:SS", `edited` from `dirty`.
- [X] T007 [P] [US1] Write `frontend/src/lib/flow/consequence.test.ts`: the exact three texts `Inspector.svelte` `consequence()` produces today (purge-audit-records with `daysToKeep` 30 and missing → `?`, purge-task-history, any other type).
- [X] T008 [P] [US1] ~~`formatCanvasStatus`~~ — not needed: the status bar already shows `snap 8 px` and `zoom NN%` (`data-testid="zoom"`), which research R-1 missed. Only `SNAP` is exported from `document.ts` and shared by the canvas and the status bar; `formatSummary`'s existing tests cover the counts.
- [X] T009 [P] [US1] Extend `frontend/src/lib/palette/search.test.ts` for `collapseGroups(groups, {limit: 3, expanded: Set<category>, query})` (data-model §4): category with 7 available → 3 shown, `hidden 4`, `total 7`; expanded category → all shown; every `available:false` entry only in `unsupported`; non-empty `query` → nothing hidden.
- [X] T010 [US1] Write `frontend/tests/us30-flow-chrome.spec.ts` (fails until T020): (a) global bar on Flows, Task catalog, Targets, Runs has the same items (mark, tabs, Dark/Light, Help, user, Sign out) and no Save/Validate/Run; (b) flow bar on a new flow: name input, "unsaved", Open…, Save, Validate, Run now, Schedule, ⋯ (New flow, Save as…, Run history); text "add a step to enable running" visible without hover; (c) empty canvas shows the explanation, the sequence/join legend, "Start from a template" (opens the example flow, spec 010 rules) and "Import from the task catalog" (opens `?view=catalog`); (d) inspector with nothing selected shows the flow name, WQM category and "Nothing selected. Click a step on the canvas and its parameters appear here."; (e) after dragging two steps into a join, `[data-testid=flow-summary]` reads "2 steps · 1 join · 0 destructive" and the status shows "snap 8 px" and "zoom"; (f) palette shows counts, "Show N more", "types not supported in v1"; typing `purge` lists a collapsed entry; (g) at 1280 × 800 every flow action is reachable (directly or in ⋯) and the page has no horizontal scroll; (h) `expectNoSeriousA11y` on Flows in dark and light. Screenshots `us30-*.png` into `specs/023-canvas-design-refresh/evidence/`.

### Implementation (US1)

- [X] T011 [P] [US1] Create `frontend/src/lib/flow/flowbar.ts` with `FlowBarState` and `flowBarState(...)` taking plain values (`steps`, `id`, `revision`, `savedAt`, `dirty`, `validating`, `scheduleBlocked`, `saving`, `name`) — no Svelte import. T006 passes.
- [X] T012 [P] [US1] Create `frontend/src/lib/flow/consequence.ts` exporting `consequence(type, parameters)` moved verbatim from `frontend/src/lib/inspector/Inspector.svelte`; import it there and delete the local function. T007 passes.
- [X] T013 [P] [US1] Export `SNAP = 8` from `frontend/src/lib/flow/document.ts` and use it in `frontend/src/lib/canvas/FlowCanvas.svelte` (instead of its local constant) and in `frontend/src/lib/shell/StatusBar.svelte` (`snap {SNAP} px`); the status bar's counts and zoom stay as they are.
- [X] T014 [P] [US1] Add `collapseGroups` in `frontend/src/lib/palette/search.ts` and use it in `frontend/src/lib/palette/Palette.svelte`: count after each category title, first 3 entries, a "Show N more" button (`aria-expanded`), a trailing "N types not supported in v1 · Show" group whose entries keep today's disabled/unavailable rendering, secondary text = `className` under each label. Expanded state is component-local. T009 passes.
- [X] T015 [US1] Create `frontend/src/lib/flow/FlowBar.svelte` (props: `editor`, `onopen`, `onsave`, `onsaveas`, `onnew`, `onvalidate`, `onrun`, `onschedule`, `onhistory`): moves from `TopBar.svelte` the name field with its rename note and `%SYS` chip and meta (now from `flowBarState`: "unsaved" badge or `rev N · saved HH:MM · edited`), then Open…, Save, Validate, Run now (primary), Schedule, and a `MenuButton` "⋯" (`aria-label="More flow actions"`) with New flow, Save as…, Run history. One visible reason text (`data-testid="flow-actions-reason"`, `role="status"`) beside the group when `flowBarState` gives one; keep the existing `title`s. At widths below 1440 the bar wraps its right group rather than overflowing (CSS only, tokens only).
- [X] T016 [US1] Reduce `frontend/src/lib/shell/TopBar.svelte` to the global items (Mark, tabs, theme switch, Help ▾, user, Sign out); remove every flow prop. Render `<FlowBar>` under it on the Flows screen in `frontend/src/routes/+page.svelte`, passing the handlers the top bar received before. Start from master's TopBar (spec 019: Overview tab, gap 5 px, tab padding 6px 5px, name min-width 72 px); with the flow controls gone, restore the roomier spacing (gap 6 px, tab padding 6px 7px) and drop the name-field rule, which moves to FlowBar; keep 019's Overview tab first.
- [X] T017 [US1] Keep `frontend/src/lib/flows/EmptyCanvasInvitation.svelte` for the spec 010 first run (no saved flows; us20/us21 assert it) and add `frontend/src/lib/flows/EmptyCanvas.svelte` for every other empty flow (`data-testid="empty-canvas"`, `pointer-events: none` on the card so drops reach the canvas): title "This flow is empty", the drag/join explanation from the board, a small legend (sequence edge, join fan-in drawn with the existing edge styles), "Start from a template" (shown only when `exampleAvailable(registry)`; calls the existing example-open path, through the unsaved-changes guard) and "Import from the task catalog" (navigates to `catalog`). In `frontend/src/routes/+page.svelte` show it whenever the open flow has zero steps and the first-run invitation is not shown.
- [X] T018 [US1] In `frontend/src/lib/inspector/Inspector.svelte`, when no step is selected render a "FLOW" section (flow name bound to `editor.name`, WQM category bound to `editor.defaultCategory` or the field the document already uses) and a "SELECTED STEP" section with "Nothing selected. Click a step on the canvas and its parameters appear here."
- [X] T019 [US1] Update `flowAction` in `frontend/tests/support.ts` to the new controls (`Open…`, `Save`, `Validate`, `Run now`, `Schedule`, ⋯ → `New flow`/`Save as…`/`Run history`) and `paletteEntry`/`expandPalette` to click "Show N more" / the unsupported group's "Show".
- [X] T020 [US1] `cd frontend && npm run check && npm test`, `bash scripts/publish-canvas.sh`, then `npx playwright test tests/us30-flow-chrome.spec.ts` and the full suite; fix regressions. Add the us30 rows (screenshot ↔ board *Proposed — flow chrome*) to `specs/023-canvas-design-refresh/evidence/README.md`.

**Checkpoint**: US1 shippable alone (MVP).

---

## Phase 4: User Story 2 — The Task catalog points at what needs attention (P2)

**Goal**: counts and the unclassified filter from the API; age and footer; detail with description,
destructive reason, "created outside SentaiTask", "Add to a flow" and a confirmed Suspend/Resume
toggle (FR-015–FR-020a). Backend change: [contracts/api-delta.md](contracts/api-delta.md).

**Independent test**: quickstart §1 and §3 on the dev instance (16 / 2 / 2 / 12).

### Tests first (US2)

- [ ] T021 [P] [US2] In `tests/sentai/unittest/catalog/TaskFilterTest.cls`: `Validate` accepts `unclassifiedOnly` ∈ `0,1,true,false` and rejects others with `INVALID_FILTER: unclassifiedOnly must be one of 0, 1, true, false`; `Matches` with `unclassifiedOnly=1` keeps only `destructiveUnknown=1`, ANDed with `filter`, `q`, `namespace`, `destructiveOnly`.
- [ ] T022 [P] [US2] In `tests/sentai/unittest/catalog/TaskReadTest.cls` (list cases use `CatalogFixtures`/`AdminApiDouble` as the existing List tests do): `counts` = `{suspended, destructive, unclassified}` over all tasks and identical with `filter=suspended` and with `unclassifiedOnly=1`; a task whose info read failed counts in no `suspended`; `description` copied verbatim from the single read, absent when empty or when the single read failed, on both List and Read. In `tests/sentai/unittest/rest/CatalogTasksTest.cls`: the route passes `unclassifiedOnly` and a bad value answers 400 with no platform call.
- [ ] T023 [P] [US2] Extend `frontend/src/lib/catalog/catalog.test.ts`: `fromWireCatalogPage` maps `counts` (absent → `unavailable`, never 0) and `description`; `catalogQuery` writes `unclassifiedOnly=1` only when set; `destructiveReason(task, registry)` → `{kind:'stepType', text: consequence(...)}` when a registry entry's `className` equals `task.class`, `{kind:'flow', flowId}` for a destructive task with `origin` and no matching class, `null` when not destructive; `outsideMark(task)` true ⇔ no `origin`; `stepFromTask(task, registry)` → draft with type, `namespace`, `runAsUser` for an available matching type, else `{ok:false, reason}` for no match / `available:false` / class absent; `suspendToggle(task)` → `checked` null when `suspended` unavailable, confirm body includes the flow warning only when `origin`; `reduceSuspendAction` gains `confirming` (`toggle` → confirming, `cancel` → idle with no send, `confirm` → pending); `catalogFiltersFromUrl`/`catalogUrl` round-trip `filter`, `unclassifiedOnly`, `task`.
- [ ] T024 [US2] Write `frontend/tests/us31-catalog-attention.spec.ts` (fails until T033): header "16 of 16 tasks · updated", Suspended 2 / Destructive 2 / "12 unclassified" (read the expected numbers from the API in the test, not hard-coded); selecting "12 unclassified" lists exactly the API's unclassified tasks; footer totals; counts unchanged when a filter is on; *Purge Tasks* detail: DESTRUCTIVE, consequence text, "classified from the step-type registry · not editable here", "created outside SentaiTask", description; a never-run task shows "No run recorded. This task has never executed on this instance."; *Integrity Check* → "Add to a flow" → Flows with an Integrity check step and "unsaved"; an undeclared class → button disabled with reason; toggle on a test-created task → confirmation → Cancel sends nothing (route spy) → Confirm → SUSPENDED and Suspended count +1 → toggle back → resumed; as a user without `%Admin_Task:USE` the refusal is shown verbatim and the toggle stays; `?view=catalog&filter=suspended` and `&unclassifiedOnly=1` open preselected; `expectNoSeriousA11y` dark/light. Screenshots `us31-*.png`.

### Implementation (US2)

- [ ] T025 [US2] `src/sentai/catalog/TaskFilter.cls`: add `unclassifiedOnly` to `Validate` and `Matches` (same accepted values as `destructiveOnly`). T021 passes.
- [ ] T026 [US2] `src/sentai/catalog/TaskShape.cls`: copy the single read's `Description` to `description` when non-empty (in `Build`). `src/sentai/catalog/TaskService.cls` `List(…, unclassifiedOnly)`: count `suspended`/`destructive`/`unclassified` on every built task before `Matches`, add `counts` to the body (numbers typed with `%Set(…, "number")`). `src/sentai/rest/Dispatcher.cls`: read `unclassifiedOnly` (default `"0"`) next to `destructiveOnly` and pass it. Load and run the whole suite: T022 passes, `All PASSED`.
- [ ] T027 [P] [US2] Update `specs/002-canvas-ui/contracts/openapi.yaml` (`CatalogPage.counts`, `CatalogTask.description`, `unclassifiedOnly` parameter) and the catalog query section of `README.md`.
- [ ] T028 [US2] `frontend/src/lib/catalog/catalog.ts` (+ `frontend/src/lib/api/client.ts` only if signatures change): implement everything T023 specifies — `counts`, `description`, `unclassifiedOnly` in `CatalogFilters`/`NO_FILTERS`/`catalogQuery`, `destructiveReason`, `outsideMark`, `stepFromTask`, `suspendToggle`, the `confirming` state, URL helpers. T023 passes.
- [ ] T029 [US2] `frontend/src/lib/catalog/CatalogScreen.svelte`: header "M of N tasks · updated N s ago" (a 1 s ticker from `readAt`) with Refresh; counts on Suspended and Destructive (hidden, not 0, when `counts` unavailable); a separate "N unclassified" toggle bound to `filters.unclassifiedOnly` with the note from FR-019 ("classification is added to the step-type catalog in a reviewed change"); footer `sorted by next run · D destructive · S suspended · U unclassified`; initial filters from the URL and URL updated on change through the page's existing navigation callback.
- [ ] T030 [US2] `frontend/src/lib/catalog/CatalogDetail.svelte`: description row; "WHY THIS IS DESTRUCTIVE" block from `destructiveReason` with "classified from the step-type registry · not editable here" (flow case: "destructive because flow N contains a destructive step", linking to the flow); "created outside SentaiTask" mark when `outsideMark`; recent runs limited to the last five with the empty text "No run recorded. This task has never executed on this instance."; replace the two buttons with one switch (`role="switch"`, `aria-checked`, label "Suspended") that opens `frontend/src/lib/shell/Modal.svelte` with `suspendToggle(task).confirm`, Confirm → existing `setSuspended`, Cancel → back to idle; disabled with the unavailable reason when `checked` is null; "Add to a flow" button (primary) calling a new `onaddtoflow(draft)` prop, disabled with the `stepFromTask` reason.
- [ ] T031 [US2] `frontend/src/routes/+page.svelte`: pass the registry to the catalog for `destructiveReason`/`stepFromTask`; implement `onaddtoflow(draft)` = `editor.addStep(draft.type, <canvas centre or next free slot>)`, then `editor.updateStep(id, {namespace, runAsUser})` for the fields present, then navigate to `flows` (the flow becomes dirty → "unsaved"). Wire "Import from the task catalog" (T017) to return to this flow.
- [ ] T032 [US2] Update `frontend/tests/us10-catalog-suspend.spec.ts` (and `catalog-support.ts` helpers) from the two buttons to toggle + confirmation, keeping its assertions on the platform's answer.
- [ ] T033 [US2] `npm run check && npm test`, publish, `npx playwright test tests/us31-catalog-attention.spec.ts tests/us7-catalog.spec.ts tests/us8-catalog-origin.spec.ts tests/us9-catalog-filters.spec.ts tests/us10-catalog-suspend.spec.ts`, then the full suite. Evidence rows (us31 ↔ board *Proposed — Task catalog*) and an API transcript of quickstart §1 in `specs/023-canvas-design-refresh/evidence/`.

**Checkpoint**: US2 shippable alone (with or without US1).

---

## Phase 5: User Story 3 — Overview points at what needs attention (P3)

**Goal**: unread summary, Needs attention and Next 24 hours above spec 019's cards (FR-022, FR-023,
FR-026, FR-029). Depends on T026 (`counts`). Spec 019's code is extended, never replaced.

**Independent test**: quickstart §4.

### Tests first (US3)

- [ ] T034 [P] [US3] Create `frontend/src/lib/overview/attention.test.ts`: attention items (backup when the `activity` card's headline `lastBackup` is empty or "Never", action disabled without a `backup` step type; suspended with names → `?view=catalog&filter=suspended`; unclassified "U of N" → `&unclassifiedOnly=1`); `ready([])` only when catalog and summary were both read; `scheduleSlots(items, now)` (half-hour buckets in `[now, now+24h)`, destructive counts, suspended apart, `flowScheduled` from `origin`, `nextAfter`); `unreadSummary(cards, bands)` → one entry per refused/unreachable `AreaCardView` and per unread band, text verbatim.
- [ ] T035 [US3] Create `frontend/tests/us32-overview-attention.spec.ts` (fails until T040): lands on Overview via `signIn(page, LANDING)`; attention items match the API; Show in catalog / Show them open the filtered catalog; the strip matches the catalog's `nextRun` within 24 h; with `/catalog/tasks` route-mocked to 403 the summary names it, Next 24 hours says so, the 11 cards still render; with one `/overview` area route-mocked `refused` the summary names that area; bands visible within 3 s; keyboard: Tab reaches every attention action and Enter follows it; `expectNoSeriousA11y` dark/light; `us29-overview.spec.ts` still passes unchanged. Screenshots `us32-*.png`.

### Implementation (US3)

- [ ] T036 [US3] Create `frontend/src/lib/overview/attention.ts` (data-model §6), reading `AreaCardView[]` from `overview.ts` and the catalog page from `lib/catalog/catalog.ts`. T034 passes.
- [ ] T037 [P] [US3] Create `frontend/src/lib/overview/UnreadSummary.svelte` (top list: what, why — platform status + message; hidden when empty) and `frontend/src/lib/overview/AttentionBand.svelte` ("NEEDS ATTENTION · N items", each with its action; "Nothing needs attention"; unread items in place).
- [ ] T038 [P] [US3] Create `frontend/src/lib/overview/ScheduleStrip.svelte` ("NEXT 24 HOURS · T tasks · D destructive · flow scheduled or not", half-hour slots with count and destructive mark, "S suspended", "then nothing until …"; "Nothing scheduled in the next 24 hours"; unread state in place).
- [ ] T039 [US3] In `frontend/src/lib/overview/OverviewScreen.svelte` (spec 019), start the catalog read concurrently with the summary through a new page callback, render UnreadSummary, AttentionBand and ScheduleStrip above the existing card sections, and make Refresh re-read both; wire "Show in catalog"/"Show them" in `frontend/src/routes/+page.svelte` to the catalog URL filters from T029.
- [ ] T040 [US3] Update `README.md` (Overview attention bands); `npm run check && npm test`, publish, `npx playwright test tests/us32-overview-attention.spec.ts tests/us29-overview.spec.ts`, then the full suite; evidence rows (us32 ↔ board *Proposed — Overview*).

**Checkpoint**: all three stories done.

---

## Phase 6: Polish & cross-cutting

- [ ] T041 [P] Complete `specs/023-canvas-design-refresh/evidence/README.md`: table file → what it proves → board it follows → FR/SC; a11y JSON per screen and theme (SC-008: 0 serious/critical); counts transcript (SC-005).
- [ ] T042 [P] [external] Moderated usability run with 5 first-time users for SC-002 (why Run now is disabled; build and validate a two-step flow from the empty state) and SC-003 (catalog counts in < 10 s); owner: product owner; notes (no names) in `specs/023-canvas-design-refresh/evidence/usability.md`.
- [ ] T043 [P] Update `docs/limitations.md` if any board element stayed out (WQM category and privilege rows, template gallery, "1 susp." slot, the board's resource table and "Run once" cards — kept as spec 019 built them) with the research reference.
- [ ] T044 Final run: backend `zpm "test sentai-task -only"` (`All PASSED`), `npm run check`, `npm test`, publish, full `npx playwright test`; `git status` clean apart from intended files; set spec.md `**Status**` per AGENTS.md (Implemented when every task is checked or `[external]`) and run `bash scripts/check-spec-status.sh`.

---

## Dependencies & execution order

```text
Phase 1 (T001–T003) → Phase 2 (T004–T005) ─┬→ US1 (T006–T020) ─────────────────────┐
                                           └→ US2 (T021–T033) ─┬────────────────────┼→ Polish (T041–T044)
                                                               └→ US3 (T034–T040) ──┘
```

- **US1** needs only Phase 2. **US2** needs only Phase 2; T031's "Import from the task catalog"
  return path touches T017's component — if US1 is not done, wire it when T017 lands.
- **US3** needs T026 (`counts`) and the catalog URL filters of T029; specs 018 and 019 are on the base.
- Within each story: tests (vitest, e2e) → pure modules → components → page wiring → suite + evidence.

## Parallel opportunities

- Phase 1: T002 ∥ T003.
- US1: T006 ∥ T007 ∥ T008 ∥ T009 (tests); then T011 ∥ T012 ∥ T013 ∥ T014 (separate modules);
  T015–T018 sequential around `+page.svelte`.
- US2: T021 ∥ T022 ∥ T023; backend (T025–T026) ∥ frontend model (T028); T027 any time after T026.
- US3: T034 first; T037 ∥ T038 (separate components) after T036.
- US1 and US2 can be built by two people at once after Phase 2.

### Example — US1 kickoff

```text
T006 flowbar.test.ts   |  T007 consequence.test.ts  |  T008 document.test.ts  |  T009 search.test.ts
→ T011 flowbar.ts      |  T012 consequence.ts       |  T013 formatCanvasStatus |  T014 collapseGroups
```

## Implementation strategy

1. **MVP = Phase 1 + Phase 2 + US1**: the flow editor is the screen every judge sees; no backend
   change; ship and demo.
2. **US2** next: one small backend change plus catalog UI; independent of US1.
3. **US3** after US2: three bands on top of spec 019's Overview, from reads the product already makes.
