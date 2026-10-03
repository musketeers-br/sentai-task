# Tasks: First-Time Canvas Tour — Three Coach Marks

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/tour.md](contracts/tour.md), [quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD, Constitution V). vitest on the pure modules and the state class;
`npm run check` after every frontend change; Playwright in `frontend/tests/us30-first-time-tour.spec.ts`
against the **baked** bundle (`bash scripts/publish-canvas.sh` after the last build), evidence into
`specs/021-first-time-tour/evidence/`. No backend change → no IRIS test tasks and no `zpm` runs.

**Hard rules**:

- The tour never opens automatically (FR-009) and persists nothing (FR-010): no storage key, no
  first-use detection, no auto-open effect anywhere in the feature.
- The spec 010 guide is untouched: no edit to `frontend/src/lib/guide/**`, `shouldAutoOpen`,
  `sentai.guide.dismissed` or the Help menu's existing entry. SC-002 is "us21 green, unedited".
- Anchors come only from [contracts/tour.md](contracts/tour.md) §3. A selector that matches
  nothing degrades to a centered card (`unionRect → null`, a value) — never a throw (Constitution IV).
- All new user-facing text is English (FR-013); the copy in [data-model.md](data-model.md) §1 is
  the required content.
- The tour never renders over a sign-in, refusal or error state (FR-011): the close rule
  (plan D-7) lands with the page wiring and its e2e case must pass before the story closes.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [X] T001 Create branch `feat/spec021` from `master` and confirm `.specify/feature.json` points at `specs/021-first-time-tour` (it already does; do not edit it further).
- [X] T002 [P] Baselines for SC-002 in `specs/021-first-time-tour/evidence/README.md` (create the evidence table skeleton from [quickstart.md](quickstart.md)): vitest case count (`cd frontend && npm test`), `npm run check` clean, e2e spec-file count, and the date of the last green full e2e run if the stack is up — this is the "before" the 0-regression claim compares against.

---

## Phase 2: Foundational (blocking)

- [X] T003 Extract the Tab-wrap from `frontend/src/lib/shell/Modal.svelte:36-53` into `frontend/src/lib/shell/dialog-focus.ts` as `export function wrapTab(dialog: HTMLDialogElement, event: KeyboardEvent): void` (same FOCUSABLE selector, same wrap rule); `Modal.svelte` imports it and its behaviour is unchanged. Proof: `npm test`, `npm run check` and `npx playwright test tests/us21-getting-started.spec.ts` (the keyboard case) all stay green — no new test file, us21 is the proof.

**Checkpoint**: the shared focus rule has one owner; `Tour.svelte` can be built on it.

---

## Phase 3: User Story 1 — Take the tour from a button (Priority: P1) 🎯 MVP

**Goal**: one visible **Tour** control on the Flows screen runs three anchored coach marks in order, with *Next* → *Done*, an identical experience on every launch.

**Independent test**: sign in → click **Tour** → "1 of 3" with the spotlight on the palette → *Next* ×2 → "3 of 3" on the validate/run controls → *Done* → gone; click **Tour** again → identical from "1 of 3" (scenario 1.8).

### Tests first

- [X] T004 [P] [US1] Unit tests, failing first (modules missing): `frontend/src/lib/tour/steps.test.ts` — exactly 3 marks; order `palette → connections → validate-run`; every `key`/anchor-selector pair matches [contracts/tour.md](contracts/tour.md) §3; bodies non-empty (FR-002, FR-013). `frontend/src/lib/tour/tour.svelte.test.ts` — `start()` opens at step 1 from any prior state; `next()` advances and clamps at the last mark; `skip()`/`finish()`/`close()` set `open = false`; a second `start()` after `finish()` is identical (FR-010); the module touches no storage (assert by reading it: no `localStorage`/`sessionStorage` reference).
- [X] T005 [P] [US1] Unit tests, failing first: `frontend/src/lib/tour/anchor.test.ts` — `unionRect`: single rect, union of two, `[]` → `null`; `pad(rect, 8)` grows by 8 on every side; `placeCard`: below with 12 px gap when there is room, flips above when the card would pass the viewport bottom, clamps x to keep 12 px inside the viewport, a target wider than the viewport still yields an on-screen card (data-model §3, spec edge case).

### Implementation

- [X] T006 [P] [US1] Implement `frontend/src/lib/tour/steps.ts` (`TOUR_STEPS`, the three rows of data-model §1 verbatim) and `frontend/src/lib/tour/tour.svelte.ts` (the state machine of data-model §2: `open`, `step`, `start`, `next`, `skip`, `finish`, `close`; singleton `tour`; no storage). T004 passes.
- [X] T007 [P] [US1] Implement `frontend/src/lib/tour/anchor.ts` (`Rect`, `Point`, `Size` plain objects; `unionRect`, `pad`, `placeCard` per data-model §3). T005 passes.
- [X] T008 [US1] Playwright first, failing (no `tour-button` exists): `frontend/tests/us30-first-time-tour.spec.ts` — (a) **Tour** visible on Flows, absent on Overview/Task catalog/Targets/Runs (FR-001); (b) the full run: click **Tour** → `getByRole('dialog', { name: 'Tour' })` shows "1 of 3", `tour-mark-body` "This is the palette — drag a step onto the canvas.", and `tour-spotlight` overlaps the `aside[aria-label="Step types"]` box; *Next* → "2 of 3" over `.canvas[role="application"]`; *Next* → "3 of 3" with the spotlight covering **both** `data-tour-target="validate"` and `"run"`; *Next* absent, primary is **Done**; *Done* → dialog gone; reopen → identical from "1 of 3" (FR-002, FR-003, FR-004, FR-005, FR-010); screenshots dark/light + `envelope` JSON into `specs/021-first-time-tour/evidence/`.
- [X] T009 [P] [US1] Create `frontend/src/lib/tour/Tour.svelte` per data-model §4: full-viewport native `<dialog>` (`showModal()`, transparent background/backdrop), SVG veil with `fill-rule="evenodd"` hole = `pad(anchorRect, 8)` rounded 8 px (`data-testid="tour-spotlight"`), card placed by `placeCard`, accessible name "Tour" (`aria-labelledby` → card `h2`), `tour-mark-body`/`tour-indicator` ("{n} of 3", `aria-live="polite"`), controls *Skip* (quiet, every mark) / *Next* (marks 1–2) / *Done* (mark 3), focus starts on the card heading, *Tab* wraps via `shell/dialog-focus.ts`, `unionRect → null` renders a centered card with no spotlight, recomputes on step change and window resize (listener only while open). Skip and Done call `tour.skip()`/`tour.finish()`.
- [X] T010 [P] [US1] `frontend/src/lib/shell/TopBar.svelte`: add `data-tour-target="validate"` to the *Validate flow* button and `data-tour-target="run"` to *Run now* (their text mutates to "Validating…", so no text selectors — contracts §3); add a secondary **Tour** button (`data-testid="tour-button"`, `onclick={ontour}`) inside a `{#if screen === 'flows'}` block immediately before the Help menu; add the `ontour` prop.
- [X] T011 [US1] `frontend/src/routes/+page.svelte`: pass `ontour={() => tour.start()}` in all five TopBar instances (the house pattern — `onhelp` is passed everywhere; rendering stays Flows-only) and render `<Tour />` in the Flows branch beside the other dialogs. T008's cases pass; `npm test`, `npm run check` green.

**Checkpoint**: the tour runs end to end from the button and is independently demonstrable.

---

## Phase 4: User Story 2 — Skip ends it, with no consequence (Priority: P1)

**Goal**: *Skip* and *Escape* end the tour at any mark, the canvas is immediately usable, focus returns to the button, and nothing is remembered.

**Independent test**: start the tour → *Skip* on mark 1 → gone, canvas usable; start → *Escape* on mark 2 → gone, focus on **Tour**; start again → identical (scenarios 2.1, 2.2).

### Tests first

- [X] T012 [US2] Playwright first, failing on the *Escape* case (Skip is wired in T009): in `frontend/tests/us30-first-time-tour.spec.ts` — *Skip* on mark 1 closes the dialog and the canvas is fully usable; start again, *Escape* on mark 2 closes it; in both paths focus returns to `tour-button`; a third start runs identically from "1 of 3" (FR-005, FR-006, FR-010, SC-003's skip half).

### Implementation

- [X] T013 [US2] In `frontend/src/lib/tour/Tour.svelte`, wire the native `cancel` event (*Escape*) to `tour.skip()`, and make every close path (Skip, Escape, Done) return focus to the element that had it before the dialog opened — the `returnFocus` pattern of `Modal.svelte` (data-model §4). T012 passes.

**Checkpoint**: the tour is dismissible from any mark by pointer and by keyboard alone.

---

## Phase 5: User Story 3 — The tour fits in without displacing anything (Priority: P2)

**Goal**: the spec 010 guide, the empty-canvas invitation and the demo hint behave exactly as before; the tour closes itself the moment the canvas stops being editable.

**Independent test**: fresh profile → the guide still auto-opens after sign-in and *Help → Getting started* still works (scenario 3.1, 3.4); with the tour open the invitation stays visible beneath and after (scenario 3.2); navigate to *Task catalog* or sign out mid-tour → the tour is gone (FR-011).

### Tests first

- [X] T014 [US3] Playwright first, failing on the close-rule cases: in `frontend/tests/us30-first-time-tour.spec.ts` — (a) coexistence: fresh profile (guide not dismissed) → the guide auto-opens as today; close it, take the tour; with the tour closed, *Help → Getting started* opens the dialog at step 1; (b) with the tour open, no other guide/dialog/hint opens automatically (scenario 3.3); (c) invitation: route `GET .../api/v1/flows` to `[]` (the us21 pattern) → the empty-canvas invitation stays attached under the tour and is visible after *Done* (scenario 3.2); (d) close rule: start the tour → click the *Task catalog* tab → the dialog is gone; start again → *Sign out* → the dialog is gone and the sign-in screen is clear (FR-011).

### Implementation

- [X] T015 [US3] In `frontend/src/routes/+page.svelte`: the close-rule `$effect` of plan D-7 — `if (phase.name !== 'ready' || screen !== 'flows' || watching !== null || session.status === 'expired') tour.close()` — and `tour.close()` inside `signOut()` next to `guide.close()`. T014 passes.

**Checkpoint**: first use is unchanged and the veil can never sit over a refusal, a run view or the sign-in overlay.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T016 [P] Verification cases in `frontend/tests/us30-first-time-tour.spec.ts`: 1024×640 viewport — the card is fully inside the viewport and the spotlight visible on every mark (spec edge case); `contrastFailures` on the open card in dark and light themes reads `[]` (the us21 theming pattern); the 1440 px fit stays clean with the Tour button present (re-assert `clipped: []`, `overflow: 0`).
- [X] T017 Full gate, no existing test edited: `cd frontend && npm test && npm run check && npm run build`, `bash scripts/publish-canvas.sh`, `npx playwright test tests/us30*`, then the full `npx playwright test` (SC-002: us21 and the whole suite green); fill the evidence table in `specs/021-first-time-tour/evidence/README.md`; `bash scripts/check-spec-status.sh` reports consistent.
- [ ] T018 [external] SC-004 usability spot-check — 3 first-time operators, [quickstart.md](quickstart.md) §6, hands-off completion of add-a-step → connect → validate → run guided only by the marks; record the count in `specs/021-first-time-tour/evidence/README.md`. Owned by the team before voting ends (2026-10-04); never blocks `Implemented`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: no dependencies. T002 can run any time after the branch exists.
- **Phase 2 (T003)**: blocks T009 (Tour.svelte uses `wrapTab`). Nothing else blocks.
- **US1 (Phase 3)**: after T003; T004/T005 parallel, T006/T007 parallel behind their tests; T009/T010 parallel (different files); T011 last — turns T008 green.
- **US2 (Phase 4)**: after T011 (the tour must run). One red case (T012), one wiring (T013).
- **US3 (Phase 5)**: after T011; T015 touches `+page.svelte`, so it follows T011/T013 sequentially.
- **Polish (Phase 6)**: after Phase 5. T018 is [external] and never blocks `Implemented`.

### Story completion order

US1 → US2 → US3 → polish. US2 and US3 both depend on US1's running tour but not on each other;
with two developers they can interleave (US2 is one component wiring, US3 is one effect), at the
cost of T013/T015 both touching files US1 just wrote — sequential is safer for a 3-hour feature.

### Parallel opportunities

- T002 alone in Phase 1; T004 ∥ T005; T006 ∥ T007; T009 ∥ T010; T016 ∥ T017's pre-publish steps.

## Implementation Strategy

### MVP First (US1, then US2)

1. Phase 1 + T003 → foundation ready.
2. Phase 3 → the tour runs from the button: **this is the demoable MVP** (the card already carries *Skip* per FR-005).
3. Phase 4 → *Escape* and focus return make it polite (both P1 stories closed).
4. Phase 5 → non-interference and the close rule (FR-008, FR-011, SC-002).
5. Phase 6 → hardening, full gate, then the [external] usability run.

Stop-and-validate points: after T011 (run us30 against the published bundle), after T013, after T015.

## Notes

- [P] = different files, no dependency on an incomplete task.
- Every task ends with its named suites green (`npm test`, `npm run check`; Playwright after `publish-canvas.sh`).
- e2e drives the **baked** bundle: `bash scripts/publish-canvas.sh` before every Playwright run that must see new code.
- The spec's rejected list is normative: no WQM screen, no new step types, no overlapping-run prevention, no dispatcher change — none of these appear here, and none may be added.
- Commit after each task or logical group; never commit secrets or evidence with credentials.
