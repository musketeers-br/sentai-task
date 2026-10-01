# Tasks: Canvas Instance Overview — Every Contest Area at a Glance

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/ui-contract.md](contracts/ui-contract.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD, Constitution V): vitest for every pure module, `npm run check`, and
Playwright `frontend/tests/us29-overview.spec.ts` against the container's baked bundle (run
`bash scripts/publish-canvas.sh` before e2e).

**Hard rules**:
- Components never call `fetch`; they use `api.*` from `src/lib/api/client.ts` and pure functions
  from `src/lib/overview/overview.ts`. Errors are values (`ApiResult`, tagged card states).
- The canvas never computes, thresholds or hides a value or an action on a guessed permission;
  the platform's words are shown verbatim.
- No "CPU", "memory" or "log" label on its own (FR-006): *Shared memory*, *CPU time (process)*.
- Nothing new in browser storage. No existing e2e test removed.
- Depends on spec 018 being merged into this branch and loaded in the container (T001).

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [x] T001 Bring spec 018 into this branch (fast-forward to `018-instance-overview-api`, which also brings `master`), point the `sentai-task-iris-1` container at this worktree, `zpm "load /home/irisowner/dev"` and check `GET /csp/sentai/api/v1/overview` answers 11 entries; record the backend suite count and the frontend baseline (`npm ci`, `npm test` count, `npm run check` clean) in `specs/019-canvas-instance-overview/evidence/README.md`.

---

## Phase 2: User Story 1 — See every area at a glance (P1) 🎯 MVP

**Goal**: *Overview* is the landing screen and shows the 11 cards from one summary read.

**Independent test**: us29 cases A (11 cards `ok` as `_SYSTEM`) and B (`SentaiDemo` account:
*Security posture* refused verbatim, allowed cards show headlines); `screen.test.ts`.

### Tests first

- [x] T002 [P] [US1] `frontend/src/lib/shell/screen.test.ts`: `screenOf` → `overview` for no `view`/`flow`/`run`; `flows` for `?flow=1`, `?run=g`, `?view=flows`; `catalog|targets|runs|overview` for their `view`; unknown `view` → `overview`; `urlForScreen(url, 'flows')` sets `view=flows` and keeps `flow`/`run`; `urlForScreen(url, 'overview')` sets `view=overview` and drops `area`.
- [x] T003 [P] [US1] `frontend/src/lib/overview/overview.test.ts` (cards): `fromWireSummary` maps each spec 018 entry to `AreaCardView` (data-model §1) in API order with the fixed labels (`processes` → "Processes", `locks` → "Locks", `memory` → "Shared memory", `activity` → "Activity", `devices` → "Devices", `licenses` → "Licenses", `web-sessions` → "Web sessions", `security` → "Security posture", `web-apps` → "Web applications", `alerts` → "System alerts", `secrets` → "Secrets"); `refused` keeps `httpStatus`, `title`, `detail`, `platformStatus` verbatim; `unreachable` keeps the detail; `headlineLines` formats each headline of spec 018 research R-3 with thousands separators and `%` only (e.g. `usedPercent: 84` → "84% of shared memory used", busiest process line), never computing a value; no label contains "CPU", "memory" or "log" alone.

### Implementation

- [x] T004 [US1] `frontend/src/lib/shell/screen.ts`: `Screen` gains `'overview'`; rules of T002 (research R-1). T002 passes.
- [x] T005 [US1] `frontend/src/lib/overview/overview.ts`: types of data-model §1, `fromWireSummary`, `headlineLines`, `refusalText(state)` → `HTTP <status> — <platform summary or detail>`. T003 passes.
- [x] T006 [US1] `frontend/src/lib/api/client.ts`: `overviewSummary()` → `request('GET', '/overview')` mapped with `fromWireSummary` (ui-contract).
- [x] T007 [US1] `frontend/src/lib/overview/AreaCard.svelte` (test ids of ui-contract: `data-testid="area-card"`, `data-area`, `data-state`, `card-refusal`) and `frontend/src/lib/overview/OverviewScreen.svelte` (loads the summary once, *Refresh*, the existing unreachable state when the API itself fails, *Retry* on an `unreachable` card re-reading the whole summary, instance and report groups in API order, read time per card).
- [x] T008 [US1] `frontend/src/lib/shell/TopBar.svelte`: *Overview* as the first tab (`aria-current` when shown); `frontend/src/routes/+page.svelte`: a `screen === 'overview'` branch rendering `OverviewScreen`, following the `runs`/`targets` branches.
- [x] T009 [US1] `frontend/tests/support.ts`: `signIn(page, query = '?view=flows', …)` (research R-2); check `us20-example-flow.spec.ts` and `us21-getting-started.spec.ts` sign in through `signIn` or pass `?view=flows` so they still land on the empty canvas.
- [x] T010 [US1] `frontend/tests/us29-overview.spec.ts` cases A and B: A — sign in with no query, expect *Overview* and 11 `area-card`s all `data-state="ok"` within 3 s (SC-001), headline text equal to the `GET /overview` response **the page itself received** (captured with `page.waitForResponse`), never a second read that could differ (SC-002); B — create a temporary account with role `SentaiDemo` through `docker exec` (as other specs create IRIS users), sign in, every card the API marked refused shows `card-refusal` with the API's status and text, `security` among them, the others `ok` (SC-003); delete the account in `afterAll`. Publish and run; save screenshots to `specs/019-canvas-instance-overview/evidence/`.

---

## Phase 3: User Story 2 — Open the full reading of an instance area (P1)

**Goal**: sortable, filterable detail views with optional auto-refresh.

**Independent test**: us29 cases C (sort/filter equal to the API) and D (hidden tab → 0 reads).

### Tests first

- [x] T011 [P] [US2] `overview.test.ts` (readings): `fromWireReading` → `ReadingView` (data-model §2); `visibleRows` sorts numbers numerically, strings case-insensitively, null last, both directions, and filters by case-insensitive substring over every cell; `rowCountLine` → "65 rows" / "65 rows · 3 shown"; column heading `CPUTime` → "CPU time (process)", computed columns marked; `readingState` after a refused refresh is `refused` (no rows kept).
- [x] T012 [P] [US2] `overview.test.ts` (auto-refresh): `createAutoRefresh({ intervalMs: 10000, read, isVisible, setTimer })` with fake timers: off by default, reads every 10 s when on, no read while `isVisible()` is false, one read resumes on becoming visible, never two reads in flight.

### Implementation

- [x] T013 [US2] `overview.ts`: `fromWireReading`, `visibleRows`, `rowCountLine`, `columnLabel`, `createAutoRefresh` (pure, timer injected). T011, T012 pass.
- [x] T014 [US2] `client.ts`: `overviewReading(area)` → `GET /overview/readings/{area}` (ui-contract).
- [x] T015 [US2] `frontend/src/lib/overview/ReadingView.svelte`: table named `<Label> rows`, sortable headers, `Filter rows` input, "N rows / M shown", read time, *Refresh*, checkbox `Auto-refresh every 10 s` wired to `createAutoRefresh` and `document.visibilitychange`; the refused/unreachable states replace the table. `OverviewScreen.svelte`: instance cards' *Open* navigates to `?view=overview&area=<id>`; the screen shows `ReadingView` when `area` names an instance area, else the cards (a non-instance `area` shows a notice).
- [x] T016 [US2] us29 cases C and D: C — open *Processes*, sort by *Commands* descending, filter by a namespace, compare the visible rows with the `GET /overview/readings/processes` response the page received (`page.waitForResponse`), since processes change between two reads; copy the address into a new page, sign in, same detail view opens; D — turn auto-refresh on, emulate a hidden page (`page.evaluate` dispatching `visibilitychange` with `document.visibilityState` overridden) for 30 s and count `/overview/readings/` requests (0), then visible again → reads resume (SC-006).

---

## Phase 4: User Story 3 — Run a report and read it where runs are read (P1)

**Goal**: report cards run their report on demand into `ResultPanel` and keep the last result.

**Independent test**: us29 case E; `overview.test.ts` card-report cases.

### Tests first

- [x] T017 [P] [US3] `overview.test.ts` (card report): `fromWireOnDemand` → `CardReport` (data-model §3) with counts from `report.summary`; `withCardReport(cards, area, report)` sets it on that card only; `withSummary(cards, newSummary)` (Refresh) keeps every card's `report`; a failed report keeps `failureReason` verbatim; `paramFindings(validationReport)` maps 422 `PARAM_*` errors to the `Finding[]` `ParameterForm` expects.

### Implementation

- [x] T018 [US3] `overview.ts`: `fromWireOnDemand`, `withCardReport`, `withSummary`, `paramFindings`. T017 passes.
- [x] T019 [US3] `client.ts`: `overviewReport(stepType, parameters)` → `POST /overview/reports/{stepType}` `{parameters}`; a 422 arrives as `kind: 'validation'` (existing handling).
- [x] T020 [US3] `AreaCard.svelte`/`OverviewScreen.svelte`: *Run report* (disabled while running, `data-state="running"`; FR-012), an optional parameters disclosure using `frontend/src/lib/inspector/ParameterForm.svelte` with `specs` from the step-type catalog the page already loads and `findings` from `paramFindings`; on answer open `frontend/src/lib/run/ResultPanel.svelte` with `{stepId: area, name: label, result: report.report}`; after close the card shows counts, ran-at and *Open report* (clarification Q2).
- [x] T021 [US3] us29 case E: run *Web applications* from its card; the panel's findings equal those of a one-step run of `web-app-inventory` opened in the run view (seed the flow and dispatch through the API helpers in `tests/support.ts`), same order (SC-005); close → card shows counts and *Open report*; *Refresh* keeps them; `GET /runs` count unchanged by the on-demand call.

---

## Phase 5: User Story 4 — Schedule this check (P2)

**Goal**: a report card becomes a scheduled one-step flow.

**Independent test**: us29 case F.

- [x] T022 [P] [US4] `overview.test.ts`: `fromWireAreaFlow` → `{flowId, hasErrors}` from spec 018's `{flow, validation}`; `canSchedule(card)` true only when `stepType` is set.
- [x] T023 [US4] `overview.ts` (`fromWireAreaFlow`, `canSchedule`) and `client.ts` `overviewFlow(area, parameters)` → `POST /overview/areas/{area}/flow`. T022 passes.
- [x] T024 [US4] `OverviewScreen.svelte` + `frontend/src/routes/+page.svelte`: *Schedule this check* on cards with a step type (and in an open on-demand report); on success navigate to `?flow=<flowId>` and, when `hasErrors` is false, set the page's `scheduling` flag once the flow is loaded so `ScheduleDialog` opens over it (research R-5); with errors the flow opens with its findings and no dialog.
- [x] T025 [US4] us29 case F: from *Secrets*, *Schedule this check* → dialog → schedule a minute ahead with the run-as password used by `us28-schedule.spec.ts`; ≤ 4 operator actions from the card (SC-004); wait for the scheduled run and open its report; unschedule and delete the flow in `afterAll`. Also: cards of instance areas show no *Schedule this check*.

---

## Phase 6: User Story 5 — Act on a process (P3, conditional)

**Build only if spec 018's T029 spike passed and its process routes exist; otherwise T027 only.**

- [x] T026 [US5] *Built: spec 018 shipped process actions (its T029 spike passed); exercised end to end by 018 quickstart 11, not by e2e on the shared instance.* If spec 018 shipped process actions: `client.ts` `processAction(pid, action, confirmation)`; `ReadingView.svelte` row actions *Suspend*, *Resume*, *Terminate* on the *Processes* view, *Terminate* asking for the pid typed exactly (the pattern of `DispatchDialog.svelte`'s typed confirmation); the platform's answer shown verbatim; the reading re-read afterwards; us29 case G on a disposable process.
- [x] T027 [US5] *Not needed: spec 018 shipped them.* If spec 018 did not ship them: no control rendered; state it in the spec's `**Status note**` and in `docs/limitations.md` next to spec 018's entry.

---

## Phase 7: Polish and cross-cutting

- [x] T028 [P] us29 case H: every address of specs 007–015 (`?flow=`, `?run=`, `?view=catalog|targets|runs`) opens what it names, never *Overview* (SC-007); paired dark/light screenshots of *Overview* with ok, refused and running cards in `evidence/` (SC-008).
- [x] T029 [P] `README.md`: *Contest areas covered* rows point at *Overview* for Operating system, Security, Web applications, Monitoring and Secrets; a still `assets/media/stills/overview.png` (from T028's light screenshot) under the demo GIF; `docs/limitations.md` gains *Overview (spec 019)*: auto-refresh only in detail views, report results kept only until reload.
- [x] T030 Full regression: `npm run check`, `npm test` (count), full `npx playwright test` (count, none removed), backend suite; record in `evidence/README.md`.
- [x] T031 Clean-up: delete `us29-` flows, runs and temporary accounts; set the spec's `**Status**` (AGENTS.md) and run `bash scripts/check-spec-status.sh`.

---

## Dependencies & execution order

- T001 blocks everything (spec 018 must be in the branch and loaded).
- US1 (Phase 2) is the MVP and blocks US2–US4 (they live on its screen); US2, US3 and US4 are
  independent of each other after US1. US5 depends on spec 018's T029 outcome only.
- `client.ts`, `overview.ts`, `OverviewScreen.svelte` and `+page.svelte` are shared: tasks touching
  the same file run in sequence.

## Parallel examples

- T002 and T003 (different test files) together; T011, T012, T017 and T022 are all in
  `overview.test.ts` — one author or sequenced.
- T028 and T029 in parallel.

## Implementation strategy

1. **MVP**: T001–T010 — the landing screen with 11 cards; the contest coverage visible in 10 s.
2. US2 (detail views), then US3 (reports), then US4 (schedule).
3. US5 only if the backend shipped it.
4. Polish, then `/speckit-analyze` before the pull request.
