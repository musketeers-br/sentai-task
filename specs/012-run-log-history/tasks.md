# Tasks: Run Log and Run History

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD). Backend: `%UnitTest` via `zpm "test sentai-task -only"` after
`$system.OBJ.LoadDir` of `src` **and** `tests` (never `DebugRunTestCase`; `git status` after every
container-side run). Frontend: vitest; Playwright against the dev stack with `iris-target` up.

**Gate after every frontend task** (from `frontend/`):
`npm test && npm run check && npm run build && bash ../scripts/publish-canvas.sh && npx playwright test <phase specs>`.

**Hard rules**: platform text verbatim and whole; a log write never changes a run (FR-004);
`GET /runs` stays an array (additive change); e2e flows use the prefixes `us24-`, `us25-`, `us26-`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [X] T001 Baseline (backend 269, unit 145, e2e 65) and measurement for SC-004: in a scratch namespace, seed 5,000 runs × 4 step runs and time the planned page query and grouped counts (research R-5). Record both in `specs/012-run-log-history/evidence/README.md`, then drop the scratch namespace.

---

## Phase 2: User Story 1 — The run log (P1) 🎯 MVP

**Independent test**: us24 — the example run's log, in order, first entry dispatch, last entry outcome.

### Tests first

- [X] T002 [P] [US1] `tests/sentai/unittest/RunNarratorTest.cls`: one test per catalog row of data-model §2 (exact text, severity, stepId); a platform text over 4000 characters split into ordered parts with nothing lost; `MarkTargetFailed` ×3 then `MarkTargetAnswered` ×2 → exactly 2 entries (SC-006); a narrator failure (simulated by a closed run id) returns an error status and never throws.
- [X] T003 [P] [US1] Add to the dispatcher tests (under the test double): `CreateRun` writes the dispatch entry; each `TransitionTo` writes its entry inside the transition; `ComputeEligibleSteps` with a failed input writes the join entry naming it; `FinalizeRun` writes the outcome with counts; a refused renewal writes the warning; entries written within one millisecond range read back in insertion order (R-2).
- [X] T004 [P] [US1] `frontend/tests/us24-run-log.spec.ts`: run the example (quickstart 1.2) and assert the panel's lines in order; run `us24-fail` (quickstart 1.3) and assert the `ERROR` line with the step's reason verbatim and the join line; open a pre-feature run (created through `tests/iris.ts` with no log) and assert "No log was recorded for runs before this version."
- [X] T005 [P] [US1] `frontend/src/lib/run/log.test.ts`: `chronological` reverses the API order, ties kept; severity labels; empty text.

### Implementation

- [X] T006 [US1] `src/sentai/dispatch/RunNarrator.cls` (catalog of data-model §2, splitting, `%down` dedupe); `LogEntry.Append` with millisecond `at`. T002 passes.
- [X] T007 [US1] Hooks: `StepRun.TransitionTo` (plan D-2), `WaveDispatcher.CreateRun`, `ComputeEligibleSteps` (D-5), `MarkTargetFailed` + new `MarkTargetAnswered` at the three success points (D-3), `RenewRunCredentialIfDue`, `FinalizeRun`; `Dispatcher.ShapeRun` orders by `at DESC, %ID DESC`. T003 passes; full backend suite green.
- [X] T008 [US1] REST control handlers (`CancelRun`, `PauseRun`, `CancelStep`, `PauseStep`, `RerunStep`) log the request and its outcome (D-4). Add a test per handler to the existing REST tests (accepted and refused, text verbatim).
- [X] T009 [US1] `frontend/src/lib/run/log.ts` and the panel in `RunScreen.svelte` (D-9). T004 and T005 pass; us4 unchanged.

**Checkpoint**: every new run tells its story.

---

## Phase 3: User Story 2 — Find and open past runs (P1)

**Independent test**: us25.

### Tests first

- [X] T010 [P] [US2] `tests/sentai/unittest/RunListTest.cls`: default limit 50; `limit=0`/`201` → 400 `LIMIT_OUT_OF_RANGE`; `state=bogus` → 400 `STATE_UNKNOWN`; `before=x` → 400 `CURSOR_INVALID`; `state` and `flowId` filters; paging with `before` has no repeats after new runs are inserted between pages; `stepCounts` count the latest attempt after a re-run; `flowName` is current after a rename; operator without SQL privilege → 403 with SQLCODE -99 text.
- [X] T011 [P] [US2] `frontend/src/lib/runs/runs.test.ts`: query ↔ address round trip; `mergePage` dedupe by `seq`; duration and counts formatting; empty-state texts.
- [X] T012 [P] [US2] `frontend/tests/us25-run-history.spec.ts`: three runs across two flows → *Runs* newest first; filter by flow → 2; filter by outcome; reload keeps filters; open the older run → read-only (no enabled *Pause*/*Cancel wave*, no *Re-run*), log shown; *Back to runs* keeps filters; *More → Run history* from the flow; with `limit` forced to 2 through the address (`&pageSize=2`, test-only query honoured by the screen), *Load more* appends without duplicates; top bar fits at 1440 px (R-3); a routed 403 on `GET /runs` shows the platform's text verbatim instead of an empty list (FR-011).

### Implementation

- [X] T013 [US2] Rewrite `Dispatcher.ListRuns` (plan D-6, research R-5); update `specs/002-canvas-ui/contracts/openapi.yaml` with `RunSummary` and the parameters (contracts/api-delta.md). T010 passes.
- [X] T014 [US2] `api/client.ts` `listRuns(query)` → `ApiResult<RunSummaryView[]>` via `wire.ts`; `screen.ts` gains `'runs'`; `lib/runs/runs.ts`. T011 passes.
- [X] T015 [US2] `lib/runs/RunsScreen.svelte`, the *Runs* tab and *More → Run history* in `TopBar.svelte`, *Back to runs* in `RunScreen.svelte`, wiring in `+page.svelte` (D-7, D-8). T012 passes.

**Checkpoint**: runs are findable.

---

## Phase 4: User Story 3 — Export (P3)

- [X] T016 [P] [US3] `frontend/src/lib/run/export.test.ts` (shape of plan D-10, file name slug, `exportedWhile` for a live run, no field from the session) and `frontend/tests/us26-run-export.spec.ts` (download event, parsed content equals `GET /runs/{guid}`'s steps and log, SC-005). See them fail.
- [X] T017 [US3] `lib/run/export.ts` and the *Export* button in `RunScreen.svelte`. T016 passes.

---

## Phase 5: Polish

- [ ] T018 Full regression (backend, unit, e2e with `iris-target` up); restore spec 002/007 evidence files the e2e run rewrote; record counts and SC-004 in `evidence/README.md`.
- [X] T019 [P] README: *Logs* area row (run log + history + export, link to this spec); "How to use" gains *Runs*; roadmap moves "run history" to done.
- [X] T020 [P] `docs/limitations.md`: SSE still does not emit `log-entry` (contracts/api-delta.md); runs dispatched before this version have no log.
- [ ] T021 Delete the `us24-`/`us25-`/`us26-` flows and their runs with `deleteFlowWithRuns` (guarded helper) after the user approves the list.

## Dependencies

- T006 blocks T007–T008; T007 blocks T009's e2e.
- T013 blocks T014–T015. Phase 3 does not depend on Phase 2, except that us25's log assertion needs T007.
- Phase 4 depends only on the existing run view.
- Spec 015 depends on this feature's *Runs* screen to show scheduled runs.
