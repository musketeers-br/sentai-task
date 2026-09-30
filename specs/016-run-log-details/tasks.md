# Tasks: Flow Execution Log Detail

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/run-view-delta.md](contracts/run-view-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD, Constitution V). Frontend only: vitest (`npm test`), svelte-check
(`npm run check`), Playwright against the published dev stack. No backend suite runs — this
feature changes no `src/` file (plan R-1).

**Gate after every task** (from `frontend/`):
`npm test && npm run check && bash ../scripts/publish-canvas.sh && npx playwright test tests/us29-step-detail.spec.ts` (the phase's specs).

**Hard rules**: platform text verbatim and whole — shown, wrapped, copied exactly (SC-002);
components never call `fetch` (all new logic in pure modules); log display logic lives in 012's `frontend/src/lib/run/log.ts` — one module (post-pull impact
note); e2e prefixes `us29-`, `us30-`, `us31-` (us27/us28 were taken by specs 013/015); an assertion that needs log **entries** is tagged blocked-by-012 and skips with
a stated reason when no entries exist — it never masquerades as passing (Constitution IV); unknown
severities pass through, never dropped.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [x] T001 Baseline and grounding: run the gate once and record the baseline (vitest methods, e2e specs passing) in `specs/016-run-log-details/evidence/README.md`; dispatch the quickstart §1 flow by hand and capture, in the same README, one `curl` of `GET /runs/{guid}` showing `steps[].result`, `executedOn` and `executedAs` as served (plan R-1 — the grounding for "no backend work"). Delete the flow afterwards (`deleteFlowWithRuns` helper, `frontend/tests/iris.ts`).

---

## Phase 2: User Story 2 — One step's execution, in full (Priority: P1) 🎯 MVP

**Goal**: selecting a step (node or row) opens its full execution account in the rail — state,
times, duration, where, as whom, failure reason whole and copyable, result readable and copyable
with its truncation markers — addressable as `?run=<guid>&step=<id>`, plus the step's log slice.

**Independent test**: `us29` — the detail, the copy round-trips and the address, on a real run
with a `db-size-report` (result) and a failing `storage-headroom-check` (reason). No dependency on
spec 012.

### Tests first (see them fail)

- [x] T002 [P] [US2] `frontend/src/lib/run/stepdetail.test.ts`: `buildStepDetail` maps state, times, duration, `executedOn`, `executedAs`, task name; a not-started step yields `—`/null for times, duration, place, identity — nothing invented (FR-011); the result block is present exactly when `hasResult` (013's `result.ts`) and its copy text equals the stored JSON exactly (SC-002, FR-009 — truncation markers shown by `ResultPanel`); the detail shows the latest attempt (existing `fromWireRun` rule) while `logSlice` carries every attempt (FR-010 via `sliceFor`).
- [x] T003 [P] [US2] Add to 012's `frontend/src/lib/run/log.test.ts`: `sliceFor(log, stepId)` keeps only that step's entries, all attempts, chronological, run-level entries excluded.
- [x] T004 [P] [US2] `frontend/tests/us29-step-detail.spec.ts`: seed the quickstart §1 flow (`01 db-size-report` → `02 storage-headroom-check` `minFreePercent: 100`) with `seedFlow`, dispatch from the UI; click node `01` → rail shows STEP DETAIL with result readable, *Copy* pastes exactly the shown JSON; open failed `02` → reason whole, verbatim, copyable; the address is `?run=<guid>&step=02`, reload keeps the selection, the close affordance deselects and drops `step`; back/forward move through selections; a `queued` step's detail shows `—` for unknowns; evidence PNG/JSON into `specs/016-run-log-details/evidence/`.

### Implementation

- [x] T005 [US2] Contract doc (post-pull: 013 already maps `result` via `resultOf` in `frontend/src/lib/run/run.ts`): document `result`, `executedOn`, `executedAs` in the `StepRun` schema of `specs/002-canvas-ui/contracts/openapi.yaml` (doc-only, [contracts/run-view-delta.md](contracts/run-view-delta.md) §1). T002's result cases pass.
- [x] T006 [P] [US2] `frontend/src/lib/run/stepdetail.ts` per data-model §2 (view model + copy texts), consuming `hasResult` from 013's `result.ts`. T002 passes.
- [x] T007 [P] [US2] `sliceFor` added to 012's `frontend/src/lib/run/log.ts` per data-model §3. T003 passes.
- [x] T008 [US2] Selection plumbing (plan D-2, house `selectTask` precedent — back closes the selection): `selectedStepId` on `RunMonitor` (`frontend/src/lib/run/monitor.svelte.ts`), synced from a new `step` prop of `RunScreen.svelte`; `onNodeClick` + step-list row click in `frontend/src/lib/run/RunScreen.svelte`; `selectStep` writing `?step=` beside `?run=` in `frontend/src/routes/+page.svelte` (data-model §5: unknown step id ⇒ silently unselected).
- [x] T009 [US2] `frontend/src/lib/run/StepDetail.svelte` in the rail above RUN LOG (plan D-3): fields, failure-reason block whole with *Copy* (D-7), and the result **reusing 013's `ResultPanel.svelte`** (embedded, gated on `hasResult`; the standalone panel gains `resultFor !== selectedStepId` so a step never renders twice — 013's `us27-area-steps` stays green) (D-11 wrap); selected-node styling in `frontend/src/lib/run/RunNode.svelte`. T004 passes.

**Checkpoint — MVP**: the step execution detail works alone, today, with no dependency on spec 012
(SC-004, SC-006 delivered). **If the deadline arrives here, ship this.**

- [ ] T010 [US2] The slice (FR-010): while a step is selected, the RUN LOG panel in `frontend/src/lib/run/RunScreen.svelte` renders `sliceFor` in chronological order; the close affordance restores the full log. US2 complete — T004's slice assertions pass.

---

## Phase 3: User Story 1 — The log, whole (Priority: P1)

**Goal**: the panel shows every entry in time order, whole and copyable, with severities readable
without colour, live updates that respect the operator's scroll, and honest empty states.

**Independent test**: `us30` — every affordance, with whatever entries exist (content assertions
guarded blocked-by-012).

### Tests first (see them fail)

- [ ] T011 [P] [US1] `frontend/src/lib/run/logview.test.ts` (live/stability): `mergeLog(prev, next)` appends only unseen entries at the chronological end, never reorders what was shown when the API's same-second ties flip (research R-3), and returns the same objects when nothing changed (referential stability, R-7); `severityLabel`: `info`→`INFO`, `warning`→`WARN`, `error`→`ERROR`, an unknown severity passes through uppercased and is never dropped.
- [ ] T012 [P] [US1] `frontend/tests/us30-log-panel.spec.ts`: severity word readable without colour in both themes (dark/light switch, `frontend/tests/theming.ts`); *Copy* on an entry pastes its full text; a long no-space message wraps and the DOM carries 100% of the text (SC-002); during a live run, scrolling up survives refreshes and *Jump to latest* returns to the newest in one action; the honest empty text shows for a run with no entries; entry-order/content assertions (first entry dispatch, order across refreshes) guarded blocked-by-012 — skip with a stated reason while no entries exist. Evidence into `specs/016-run-log-details/evidence/`.

### Implementation

- [ ] T013 [US1] Panel upgrade in `frontend/src/lib/run/RunScreen.svelte` using `logview.ts`: chronological + keyed `mergeLog` per poll (merge, not replace), `INFO`/`WARN`/`ERROR` text labels beside colour in both themes, *Copy* per entry (D-7), follow behaviour + *Jump to latest* (D-8), wrap-anywhere (D-11), honest empty text (D-10 — 012's wording once it lands). T011 and T012 pass; `us4` unchanged.

**Checkpoint**: both P1 stories done — the log is readable, whole, copyable, and every step's
account is one click away.

---

## Phase 4: User Story 3 — Find the entry that matters (Priority: P2) ✂️ cut first at the deadline

**Goal**: severity narrowing composable with the step slice, "N of M" counts, one-action clear.

**Independent test**: `us31`.

### Tests first (see them fail)

- [ ] T014 [P] [US3] `frontend/src/lib/run/logview.test.ts` (filters): `narrow(entries, {severity, stepId})` composes severity with the slice; `counts` yields `{shown, total}` → "N of M"; a match of nothing is an honest empty, not an error (FR-013).
- [ ] T015 [P] [US3] `frontend/tests/us31-log-filters.spec.ts`: narrow by severity shows only matching entries with "N of M"; combined with a selected step both apply; one action clears; a filter matching nothing says so honestly; live + filtered gains a new matching entry — blocked-by-012 guarded (skip with reason while no entries exist). Evidence into `specs/016-run-log-details/evidence/`.

### Implementation

- [ ] T016 [US3] `narrow` + `counts` in `frontend/src/lib/run/logview.ts` and the filter control in the RUN LOG section of `frontend/src/lib/run/RunScreen.svelte` (screen-only state, not addressed). T014 and T015 pass.

**Checkpoint**: all stories done. Nothing else depends on this phase — skipping it entirely is a
clean cut.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T017 Full regression and evidence: `npm test && npm run check && npm run build && bash ../scripts/publish-canvas.sh`, then the whole Playwright suite with `iris-target` up (~6 min); restore any evidence files of other specs the e2e run rewrote; record final counts and the SC-002/SC-003 results (a 500-entry `mergeLog` timing if feasible) in `specs/016-run-log-details/evidence/README.md`.
- [ ] T018 [P] `README.md`: the *Logs* area row gains the step execution detail (result visible, reason whole, copyable) linking to `specs/016-run-log-details/`; *How to use → Watch* mentions clicking a step for its account.
- [ ] T019 Delete the `us29-`/`us30-`/`us31-` flows and their runs with `deleteFlowWithRuns` (`frontend/tests/iris.ts`) after the user approves the list.

---

## Dependencies & Execution Order

### Phase and task dependencies

- T001 first (baseline + grounding). T002, T003, T004 are independent test files — parallel.
- T005 blocks T006 and T007 (both consume the `result` mapping / types); T006 ∥ T007 after it.
- T006/T007 block T008 (selection needs the view models); T008 blocks T009; **T009 = MVP
  checkpoint**; T010 (slice) completes US2 and needs T007's `sliceFor` + T009's rail.
- Phase 3: T011 ∥ T012; T013 needs T010 (same file, `RunScreen.svelte`) and T007.
- Phase 4: T014 ∥ T015; T016 needs T013. **Phase 4 is cuttable whole** — no other phase depends
  on it.
- Phase 5 after all kept phases; T019 after user approval.

### User story completion order

US2 (MVP, no 012 dependency) → US1 → US3 (cut first). Within every story: tests fail first, then
pure modules, then components, then e2e green.

### Parallel example: Phase 2 tests

```bash
# Three independent test files — write and see them fail together:
Task T002: frontend/src/lib/run/stepdetail.test.ts
Task T003: frontend/src/lib/run/logview.test.ts
Task T004: frontend/tests/us27-step-detail.spec.ts
```

## Implementation Strategy (deadline risk — MVP first)

1. T001 → Phase 2 through **T009**, then **STOP and VALIDATE**: `us29` green on the published
   canvas — this is the MVP (step detail incl. result; works with zero dependency on spec 012).
   Demo it.
2. T010 completes US2 cheaply (the slice's pure logic already exists at T007).
3. Phase 3 (US1): the log reading experience — its visible payoff grows the moment spec 012's
   recording lands; all affordances land and are verified regardless.
4. Phase 4 (US3): **first thing to cut** when the deadline moves; nothing breaks without it.
5. Phase 5 always; T018/T019 can land even if Phase 4 was cut.

Stopping after any phase leaves the product better and nothing half-built.

## Notes

- [P] = different files, no dependency on incomplete tasks; [Story] maps to spec.md.
- Every task runs the gate above before being considered done.
- Commit after each task or logical group; evidence README rows after T001, T004/T012/T015, T017.
