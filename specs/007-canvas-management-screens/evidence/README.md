# Evidence — 007 Canvas Management Screens

Captured on 2026-09-27 against the dev container (IRIS 2026.2), canvas build published with
`scripts/publish-canvas.sh`. No password, token or refresh credential appears in any file here.

## Status

**Everything is done.** Part A (task catalog) and T009 (typed confirmation) first; Part B (T007,
T008, T010 and the Part B half of T011) on 2026-09-27, built in the existing visual system — spec
009 Clarifications Q1 = A replaced the T001 prototype with paired dark/light screenshots
(`sc008-params-*.png`). BD-1 and BD-2 are delivered in spec 005.

## Test counts

| Suite | Before 007 | Now | Added | Removed |
|---|---|---|---|---|
| Unit (vitest) | 48 | 73 | 25 (catalog 23, typed confirmation 2) | 0 |
| End-to-end (Playwright) | 13 | 22 | 9 (us7 ×2, us8, us9 ×2, us10 ×2, us13, us14) | 0 |

`us14` runs only under gate G-C (see below) and is skipped otherwise, so a normal run reports
21 passed and 1 skipped.

**Adjusted, not removed:** `us4` "Dispatch is refused for a flow with steps unsupported in v1".
Its flow has a destructive step, so it now types the confirmation before *Dispatch*; its
assertions are unchanged.

## Success criteria

| SC | Result | Evidence |
|---|---|---|
| SC-001 values equal the API | **Met.** Every row and cell of all 16 tasks equals `GET /catalog/tasks`, and every detail field equals the item read for the tasks checked | `us1-values.json`, `us1-details.json` (us7) |
| SC-002 N marked rows, flow in ≤ 2 clicks | **Met.** A scheduled 3-step flow gives exactly 3 rows marked `flow <id> · step 01/02/03`; row click + origin link opens the flow; a deleted flow reads *flow not found*, no link | `us2-origin.json` (us8) |
| SC-003 < 3 s first rows, < 2 s filter | **Met** with 151 tasks: first rows about 1.4 s, filter update about 1.37 s including the 300 ms debounce, over 3 runs | `sc003-timing.txt` (us9) |
| SC-004 suspend/resume confirmed; refusals show the status | **Met.** Suspend and resume on a task the test scheduled, each confirmed by a fresh read; an operator without `%Admin_Task` sees `HTTP 403 — no reason given` (list and detail) | `us4-suspend.json` (us10, us7) |
| SC-005 parameter form | **Met.** `storage-headroom-check` shows exactly its one declared field (number, 0–100, placeholder `default: 10`, the API description); `db-size-report` "takes no parameters"; `PARAM_OUT_OF_RANGE` carried `parameter` and was shown on its field, verbatim; clearing the field removes the key | `us5-params.json` (us11) |
| SC-006 three destructive signals | **Met.** `purge-task-history` from the Custom group carries the hazard band, the DESTRUCTIVE seal and the purge border (us12), and the typed confirmation (us14) | us12, `us6-typed-confirmation.json` |
| SC-007 existing tests green, one e2e per story | **Met,** with the one adjustment above; US-1…US-4 and US-6's confirmation each have their own e2e | full run 2026-09-27 |
| SC-008 paired theme screenshots | **Met** for the catalog and the parameter form with a field in error (same strings, every text ≥ 4.5:1) | `sc008-catalog-*.png`, `sc008-params-*.png` (us13) |

## Gate G-C (typed confirmation e2e)

`purge-task-history` was set `available: true` in the working tree only, compiled on the dev
container, `us14` was run, then the file was restored with `git checkout` and recompiled.
`GET /catalog/step-types` then reported it `available: false`. Details and the run it created are
in `us6-typed-confirmation.json`. With T009 merged, spec 005 T016 may now commit that flip.

## Findings while running

- The dev container was running classes from before spec 006. It was synced with
  `$system.OBJ.LoadDir` (plain `zpm load` did not import the new classes), and the
  `SentaiWebPage` role from `iris.script` was created so the static app matches `module.xml`.
- The theming check found "—" (no value) below 4.5:1 in the dark theme; it now uses the muted
  text token.

## Part B findings (2026-09-27)

- The third top-bar tab (spec 009) made the bar overflow at 1440 px: "Task catalog" wrapped,
  "Light" and later "Sign out" were clipped. The flow name now gives way first and the gaps are
  tighter; no item passes 1440 px.
- The inspector's "runs on this instance only" note (spec 009) took the destructive block's red
  `.note` style; it has its own muted style now.
