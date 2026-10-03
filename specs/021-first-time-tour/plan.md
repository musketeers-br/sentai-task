# Implementation Plan: First-Time Canvas Tour — Three Coach Marks

**Branch**: `feat/spec021` (feature dir `021-first-time-tour`; no branch exists yet — no git hook is installed) | **Date**: 2026-10-01 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (1 answered clarification, 14 FRs, 4 SCs). Frontend-only: the Svelte
canvas in `frontend/src`. The tour is launched from a button and stores nothing, so there is **no
backend change, no wire change, and no browser storage**. One small UI contract,
[contracts/tour.md](contracts/tour.md), records the anchor registry the marks and the e2e share.

## Summary

One control, three marks, no state:

1. **The button (FR-001)**. `TopBar` gains a secondary **Tour** button on the Flows screen, before
   *Help*, wired through a new `ontour` prop to `tour.start()` in `+page.svelte`. The flexible name
   field absorbs the ~55 px ([research R-4](research.md)); the 1440 px fit check stays.
2. **The overlay (FR-002…FR-007)**. A full-viewport native `<dialog>` (`showModal`, transparent
   backdrop) draws an SVG veil with a rounded cut-out — the *spotlight* — over the current mark's
   anchor elements, and a message card beside it. The page behind is inert, so no stray drag can
   happen mid-tour. *Next* advances, *Done* finishes, *Skip* (and native *Escape* → `cancel`)
   ends the tour at any mark. The focus-wrap logic leaves `Modal.svelte` and becomes
   `shell/dialog-focus.ts`, shared by both dialogs.
3. **No memory (FR-008…FR-010)**. The *Getting started* dialog (spec 010) is untouched — the tour
   never opens automatically and reads/writes no storage at all. Reopening is always identical
   from mark 1. The page closes the tour when the canvas stops being editable (navigate away,
   open a run, sign out, session expires), so the veil can never sit over a refusal or the
   sign-in overlay (FR-011).

## Technical Context

**Language/Version**: TypeScript 5.9, Svelte 5 (runes), SvelteKit 2 (`adapter-static`, one
prerendered page, `ssr = false`), as in specs 002, 007, 009 and 010. The backend (ObjectScript on
IRIS 2026.2) is **not changed**.

**Primary Dependencies**: none new. `@xyflow/svelte` is unchanged; no tour library
([research R-6](research.md)).

**Storage**: **none** (FR-010). The tour writes nothing to `sessionStorage`, `localStorage` or the
server, and reads nothing. It is the first onboarding surface with zero storage surface.

**Testing**:
- vitest on the pure geometry (`tour/anchor.ts`) and the state class (`tour/tour.svelte.ts`).
- Playwright `tests/us30-first-time-tour.spec.ts` against the compose stack (baked bundle; publish
  first), evidence into `specs/021-first-time-tour/evidence/`.
- IRIS tests: none; no ObjectScript changes.

**Target Platform**: Chromium, Firefox and WebKit through Playwright, as the existing suite. The
static app is served by IRIS at `/csp/sentai/`.

**Project Type**: web application (frontend slice only).

**Performance Goals**: none worth a budget — the overlay is static geometry computed on click and
on resize; no request is made. A mark appears within one frame of the click.

**Constraints**:
- No automatic opening, ever (FR-009) — the only entry is the button.
- Nothing persisted (FR-010).
- No backend or contract change beyond [contracts/tour.md](contracts/tour.md) (a UI contract).
- All new text in English (FR-013).
- The top bar still fits at 1440 px (us21's fit check now includes the Tour button).
- The ~3 hours of the input is the budget: the marks + button + skip are the core; keyboard/a11y
  and the close rule are part of the core because the spec makes them FRs, not polish.

**Scale/Scope**: 1 new feature folder (`lib/tour`, 4 files), 1 new shared module
(`shell/dialog-focus.ts`), 3 touched files (`TopBar.svelte`, `+page.svelte`, `Modal.svelte`),
~14 unit cases, ~9 e2e scenarios in 1 new spec file. No existing test is edited on purpose.

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 (see end). Every row passes; no
Complexity Tracking entries.*

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | Components (`Tour.svelte`) → state class (`tour/tour.svelte.ts`) → pure modules (`tour/anchor.ts` geometry, `tour/steps.ts` content). The component is the only place that touches the DOM (reads anchor rects); geometry is pure and unit-tested. `TopBar` learns nothing about the tour beyond an `ontour` callback prop, and `+page.svelte` wires it, exactly like `onhelp`. No `fetch`, no storage, no HTTP anywhere in the feature. | ✅ |
| **II Closed Capability Set** | No new operation, no new capability. The three marks are fixed typed data in the codebase; the button calls a fixed function. Nothing the operator types or drops is evaluated anywhere on the tour's path. | ✅ |
| **III Delegated Authorization** | The tour makes no request and stores nothing — no permission, role or credential is read, kept or cached. Trivially compliant; the e2e storage audit from spec 010 keeps passing untouched. | ✅ |
| **IV Errors as Values** | One predictable failure exists: an anchor selector that no longer matches (a DOM refactor). `unionRect` returns `null` for that mark, a value the component renders as a centered card without a spotlight — it never throws across the boundary ([data-model §3](data-model.md)). | ✅ |
| **V Verifiable Increments** | Two increments, each user-observable with its failing e2e first (see *Increments*). None is a layer ticket: increment 1 delivers the whole tour behaviour a user can take; increment 2 delivers the politeness a user feels (keyboard, never over a refusal). | ✅ |
| **VI Technology Agnosticism** | Technology appears only here and in research. The spec and constitution are untouched. | ✅ |
| SOLID / SoC | One reason to change per module: content (`steps.ts`), transitions (`tour.svelte.ts`), geometry (`anchor.ts`), presentation (`Tour.svelte`), dialog focus rules (`shell/dialog-focus.ts` — extracted from `Modal.svelte`, which had two reasons to change before). | ✅ |
| TDD | Every task starts with the failing test: vitest for geometry and transitions, Playwright for the observable behaviour (see *Testing Strategy*). | ✅ |
| YAGNI | No storage, no first-use detection, no replay memory, no analytics, no i18n, no third-party tour engine, no advancement-on-real-action — each was considered and rejected ([research R-1, R-6](research.md)). | ✅ |
| Reproducibility | No new toolchain. `docker compose up`, `npm ci`, `publish-canvas.sh`, `npx playwright test`, as today. | ✅ |

## Decisions

- **D-1 The button (FR-001).** A secondary **Tour** button in `TopBar`, rendered only when
  `screen === 'flows'`, placed just before the *Help* menu, `data-testid="tour-button"`. New
  `ontour` prop; `+page.svelte` passes `ontour={() => tour.start()}` in the Flows branch (the
  other TopBar instances keep a no-op-free omission — the button simply isn't rendered
  elsewhere). *Run history* (spec 012) is the precedent for a Flows-only action in the bar.
  **Implementation note (2026-10-01)**: the bar already fits *exactly* at 1440 px — adding the
  button clipped *Sign out* by 36 px (us21's fit check caught it, as designed). The button
  moved to the canvas' free top-right corner (`+page.svelte`, `.canvas-tour`, still
  `data-testid="tour-button"`, one action, Flows branch only), which FR-001 allows — the spec
  asks for a visible one-action control on the canvas screen, not a place in the bar. The
  `ontour` prop was dropped with it.
- **D-2 The overlay (FR-002, FR-003, FR-007).** One full-viewport native `<dialog>`
  (`Tour.svelte`): `width/height: 100%`, transparent background and backdrop; inside it an SVG
  veil (viewport-sized `path` with `fill-rule="evenodd"`, hole = anchor rect + 8 px padding,
  8 px corner radius) and the message card positioned absolutely. Native `showModal` gives the
  top layer (the veil sits above the empty-canvas invitation, which stays attached beneath —
  FR-007 needs nothing), makes the page inert (no accidental drags), and fires `cancel` on
  *Escape* — the same primitives `Modal.svelte` already proved in us21. Alternatives:
  [research R-2](research.md).
- **D-3 Anchors (FR-003, [contracts/tour.md](contracts/tour.md)).**
  - mark 1 — the palette: existing `aside[aria-label="Step types"]` (`Palette.svelte:56`);
  - mark 2 — the connection surface: existing `.canvas[role="application"]`
    (`FlowCanvas.svelte:55`), which exists on every editable canvas, empty or not;
  - mark 3 — the validate/run controls: the two `TopBar` buttons. Their visible text mutates
    ("Validating…"), so they get stable `data-tour-target="validate"` / `"run"` attributes and
    the mark anchors the **union** of both rects (`unionRect`).
  Nothing else gets an attribute; the e2e asserts spotlight/anchor overlap, so a refactor that
  breaks an anchor fails us30 rather than silently mis-pointing.
- **D-4 Geometry (pure, `tour/anchor.ts`).** `Rect` is a plain object; the component converts
  `getBoundingClientRect()` at the edge. `unionRect(rects): Rect | null`. `placeCard(target,
  viewport, card): Point` prefers 12 px below the target, flips above when the viewport lacks
  room, and clamps 12 px inside the viewport horizontally ([data-model §3](data-model.md)).
  Recomputed on step change and on window resize (listener registered only while open). No
  scroll handling: the app is a fixed full-viewport flex layout with no page scroll
  (`+page.svelte` `.app { height: 100% }`) — [research R-8](research.md).
- **D-5 State (`tour/tour.svelte.ts`, singleton `tour`).** `open`, `step` (1-based), the fixed
  `TOUR_STEPS` (3). `start()` always resets to step 1 and opens (identical every launch,
  FR-010); `next()` clamps at the last; `skip()` and `finish()` both just close. No preference
  module, no visit flag, no storage — the entire spec 010 guide machinery is deliberately not
  built here ([research R-1](research.md)).
- **D-6 Dialog semantics (FR-004, FR-005, FR-006).** Accessible name **"Tour"**
  (`aria-labelledby` → the card's `h2`); the message is `aria-describedby` →
  `data-testid="tour-mark-body"`; the indicator "1 of 3" is `aria-live="polite"` at
  `data-testid="tour-indicator"`. Controls per mark: *Skip* (quiet), *Next* (primary, marks 1–2),
  *Done* (primary, mark 3). Focus starts on the card heading (`autofocus`, `tabindex="-1"`,
  as the guide does), *Tab* wraps inside via the extracted `shell/dialog-focus.ts` (`Modal` now
  imports it too — same behaviour, one owner), *Escape* → native `cancel` → `skip()`, and focus
  returns to the Tour button (the `returnFocus` pattern from `Modal.svelte`).
- **D-7 The close rule (FR-011).** One `$effect` in `+page.svelte`:
  `if (phase.name !== 'ready' || screen !== 'flows' || watching !== null || session.status ===
  'expired') tour.close()`. These are exactly the four ways the canvas stops being editable
  ([research R-5](research.md)); `signOut()` also calls `tour.close()`, like `guide.close()`.
  The tour therefore never renders over the sign-in overlay, a refusal or a run view, and no
  platform message is ever dimmed under the veil.
- **D-8 No change to first use (FR-008, FR-009).** `guide.*`, `shouldAutoOpen`,
  `preference.ts` and the Help menu are untouched. Because the tour never auto-opens,
  `support.ts` needs no seed for it and no existing e2e is edited ([research R-7](research.md)).

## Project Structure

### Documentation (this feature)

```text
specs/021-first-time-tour/
├── spec.md
├── plan.md              # this file
├── research.md          # R-1 … R-9 (findings, decisions, rejected alternatives)
├── data-model.md        # Tour mark, Tour state machine, anchor geometry, dialog semantics
├── contracts/tour.md    # the UI contract: anchors, testids, accessible name, close rule
├── quickstart.md        # manual script SC-001 … SC-004 + automated commands
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks (not created here)
```

### Source Code

```text
frontend/src/lib/
├── tour/                                    # NEW — the coach-mark tour (US1, US2)
│   ├── steps.ts, steps.test.ts              # TOUR_STEPS: 3 marks, order, anchor keys, English copy
│   ├── anchor.ts, anchor.test.ts            # Rect, unionRect, placeCard (pure geometry)
│   ├── tour.svelte.ts, tour.svelte.test.ts   # open/step/start/next/skip/finish — no storage
│   └── Tour.svelte                          # NEW — dialog + SVG veil + spotlight + card
├── shell/
│   ├── dialog-focus.ts                      # NEW wrapTab(dialog, event) — extracted from Modal
│   ├── Modal.svelte                         # TOUCH — uses dialog-focus.ts (behaviour unchanged)
│   └── TopBar.svelte                        # TOUCH — Tour button (Flows only), data-tour-target on
│                                            #        Validate flow / Run now, ontour prop
frontend/src/routes/+page.svelte             # TOUCH — ontour wiring, <Tour />, the close-rule effect,
                                             #         tour.close() in signOut()
frontend/tests/
└── us30-first-time-tour.spec.ts             # NEW — SC-001…SC-003, evidence into specs/021…/evidence/
```

**Structure decision**: the existing SvelteKit app, one new feature folder `lib/tour` following
`lib/guide` (its sibling onboarding feature). The only shared-code change is the extraction of
the focus wrap into `shell/dialog-focus.ts` — reviewed as part of increment 2. `src/sentai/**`
(ObjectScript) is not touched.

**Existing-suite impact**: none. The tour never auto-opens, so no test needs a seed; the new
button joins us21's 1440 px fit check automatically (it must pass); `Modal.svelte`'s behaviour is
identical after the extraction, which us21's keyboard test re-proves.

## Increments (Constitution V)

| # | Increment (observable) | Depends on | First failing test |
|---|---|---|---|
| 1 | The tour runs from the button: 3 marks in order, each spotlighting its anchor with its message, *Next* → *Done*, *Skip* anywhere, identical on reopening (US1, US2 core) | — | `us30`: click **Tour** → dialog "Tour" shows "1 of 3"; the spotlight box overlaps the palette box; *Next* ×2 → "3 of 3" → *Done* → gone; reopen → "1 of 3" again |
| 2 | The tour is polite: keyboard-only traversal, *Escape* skips, focus returns to the button; it closes itself when the canvas stops being editable; card never leaves the viewport; both themes read (US3, FR-006, FR-011, edge cases) | 1 | `us30`: start tour → Tab ×15 stays inside; *Escape* → gone, focus on **Tour**; start tour → click *Task catalog* → gone; 1024×640 → card fully inside the viewport |

## Testing Strategy

**TDD**: the failing test first, for the reason the task fixes. Unit for pure logic, Playwright
for observable behaviour (Constitution V).

**Unit (vitest)**, ~14 cases:
- `tour/anchor.test.ts`:
  - `unionRect`: single rect; union of two adjacent rects; `[]` → `null` (the value, never a
    throw);
  - `placeCard`: below when there is room; flips above when there is not; clamps horizontally at
    12 px; a target wider than the viewport still yields an on-screen card.
- `tour/tour.svelte.test.ts`: `start()` opens at step 1 from any prior state; `next()` stops at
  the last mark; `skip()`/`finish()` close; reopening after finish is identical (no storage to
  clear — the test documents FR-010 by construction).
- `tour/steps.test.ts`: exactly 3 marks; keys in the order palette → connections →
  validate-and-run; every anchor key resolves to declared selectors; English copy present.

**End-to-end (Playwright, compose stack)**, ~9 scenarios in `us30-first-time-tour.spec.ts`:
- button visible on Flows, absent on Overview/Catalog/Targets/Runs (FR-001);
- the three marks in order, each with its message and "n of 3"; the spotlight element
  (`data-tour-spotlight`) overlaps its anchor box (palette, canvas, the validate-run union);
  screenshots dark/light into evidence (FR-002, FR-003, FR-004);
- *Next* advances, *Done* ends, reopen identical (FR-005, FR-010);
- *Skip* on mark 1 and *Escape* on mark 2 both end it; focus returns to the Tour button
  (FR-005, FR-006);
- keyboard-only: Tab ×15 stays inside `dialog[open]`; announced `role="dialog"` name "Tour"
  (FR-006, SC-003);
- closing on state change: start tour → navigate to *Task catalog* → gone; start → *Sign out* →
  gone (FR-011);
- the invitation stays: routed empty flow list → start tour → `example-invitation` attached
  beneath; still visible after *Done* (FR-007);
- 1024×640 viewport: card fully inside, no element clipped (edge case);
- 1440 px fit check unchanged (us21's, re-run here as a guard) and contrast pass on the card in
  both themes via `contrastFailures` (theming).

**Commands**: `cd frontend && npm test && npm run check && npm run build`, `bash
scripts/publish-canvas.sh`, `npx playwright test tests/us30*`, then the full
`npx playwright test` for regressions.

### Success criteria: automated vs manual

| SC | Automated | Manual (quickstart) |
|---|---|---|
| SC-001 one action → 3 marks in order, anchored | ✅ `us30` (start, order, spotlight/anchor overlap) | ✅ visual pass: the spotlight really sits on the palette/canvas/buttons |
| SC-002 0 regressions to the *Getting started* dialog | ✅ full suite (`us21` unchanged and green) | ✅ fresh profile: dialog still auto-opens once |
| SC-003 keyboard-only: traverse, finish, Escape-skip | ✅ `us30` | ✅ unplug the mouse |
| SC-004 3 of 3 first-time operators complete the loop guided only by the marks | ⚠ the e2e proves the marks carry the content; completion needs people | ✅ **manual**: 3 operators, the quickstart script, count hands-off completions |

## Risks

| Risk | Mitigation |
|---|---|
| The Tour button breaks the 1440 px fit | The name field flexes (`flex: 0 1 240px; min-width: 72px`) and absorbs the ~55 px ([R-4](research.md)); us21's fit check now covers the button and fails loudly. |
| A later refactor moves an anchor element | The e2e asserts spotlight/anchor overlap, so us30 fails instead of the tour pointing at nothing. Missing anchors degrade to a centered card (`unionRect → null`), never a throw. |
| The veil dims a platform refusal | Impossible by construction: the tour opens only from the button on the editable canvas, and the close rule (D-7) dismisses it on the first state change. |
| `showModal` inertness blocks a mid-tour action the operator wanted to do | *Next* always advances without requiring the real action (spec Assumptions); *Skip* is one click away; the tour changes no state, so nothing is lost by skipping and restarting. |
| Scope creep past the 3-hour budget | The spec's rejected list is normative; this plan adds no storage, no library, no second entry point. |

## Complexity Tracking

No constitutional violations; nothing to justify.

## Post-Design Constitution Re-check

Re-evaluated after writing [research.md](research.md), [data-model.md](data-model.md) and
[contracts/tour.md](contracts/tour.md):

- **I**: DOM reads only in the component; geometry pure; no cross-layer shortcut.
- **II**: no new capability; marks are fixed data.
- **III**: no request, no storage, nothing cached.
- **IV**: the one predictable failure (missing anchor) is a value.
- **V**: two observable increments, failing e2e first.
- **VI**: technology only here.

**Gate: PASS.**
