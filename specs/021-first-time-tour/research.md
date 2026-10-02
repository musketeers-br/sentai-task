# Research: First-Time Canvas Tour — Three Coach Marks

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Date**: 2026-10-01

This feature is frontend-only and adds no request, so nothing needed live probing against the
stack. Every finding below is read from the current tree (with `file:line`) or from the
behaviour the already-green e2e suite proves (`us21`), and each decision names its rejected
alternative.

---

## R-1 What the tour deliberately does not build

**Decision**: No automatic opening, no storage, no preference module, no visit logic. The button
is the only entry (spec FR-001, FR-009, FR-010).

**Findings**: Spec 010's guide needed `preference.ts` (localStorage `sentai.guide.dismissed`),
`shouldAutoOpen(origin, dismissed, shownThisVisit)` and `resetVisit()` — three concepts, one
e2e seed in `support.ts`, and a storage-blocked edge case to test — because it *opens by
itself*. The tour does not, so every one of those concepts is unbuilt here. The spec's
clarification Q1 made this explicit: the *Getting started* dialog keeps its role untouched and
the tour is opt-in.

**Alternatives rejected**:
- *Auto-open once per browser (the original draft)* — rejected by Q1; it would also re-import
  the whole preference machinery for no voter-visible gain.
- *"Seen" memory so the button can look different after the first tour* — YAGNI; the spec says
  every launch behaves identically (FR-010), and nothing consumes such a flag.

---

## R-2 The overlay: a native dialog with an SVG veil

**Decision**: one full-viewport native `<dialog>` (`showModal()`), transparent background and
backdrop, containing a viewport-sized SVG path (`fill-rule="evenodd"`) whose hole is the
anchor rect plus 8 px padding, and the message card positioned absolutely inside the dialog.

**Findings**:
- `showModal()` gives, for free, exactly what FR-005/FR-006/FR-007 need: the top layer (above
  the empty-canvas invitation, which stays attached beneath), a page made inert behind (no
  accidental palette drag mid-tour), and *Escape* → `cancel` event. `Modal.svelte`
  (`frontend/src/lib/shell/Modal.svelte:27-34`) already relies on these primitives, and
  `us21-getting-started.spec.ts:72-90` proves them in this app: `dialog[open]`,
  `aria-modal`, Tab staying inside, *Escape* closing, focus returning to the invoker.
- Styling a native dialog as a full-viewport overlay is plain CSS (`margin: 0; width/height:
  100%; background: transparent; border: none;`) — no library needed.
- The SVG `evenodd` veil draws the rounded hole in one element, so the spotlight ring is theme-
  able with the existing token set (`--color-border` for the ring, card tokens for the card).

**Alternatives rejected**:
- *`box-shadow: 0 0 0 9999px rgba(...)` on a spotlight div* — the classic trick, but the spread
  is viewport-dependent, the "hole" cannot be rounded independently of the card, and it paints
  a huge layer per frame.
- *`clip-path` on an overlay* — two composed layers for the same result, and no ring.
- *A plain `div` with `role="dialog"`* — loses the top layer, inertness and native *Escape*;
  the tour would reimplement what the browser already guarantees.
- *`driver.js` / `shepherd.js` / `intro.js`* — see R-6.

---

## R-3 The three anchors exist today and how to select them

**Decision**: anchor by stable attributes, recorded in
[contracts/tour.md](contracts/tour.md); the two top-bar buttons get new `data-tour-target`
attributes because their visible text mutates.

**Findings** (read from the tree, 2026-10-01):

| Mark | Anchor element | Stable selector today | Action needed |
|---|---|---|---|
| 1 palette | `aside.palette` | `aside[aria-label="Step types"]` — `Palette.svelte:56` | none |
| 2 connection surface | `.canvas` | `.canvas[role="application"][aria-label="Flow canvas"]` — `FlowCanvas.svelte:55` | none |
| 3 validate & run | the two `TopBar` buttons — `TopBar.svelte:128-144` | none stable: *Validate flow* becomes "Validating…" while busy | add `data-tour-target="validate"` / `"run"`, anchor the **union** of the two rects |

- The palette and the canvas exist on every editable canvas regardless of the open flow
  (empty, the operator's, the example, the showcase) — the spec's scenario 1.6 costs nothing.
- The two buttons are adjacent siblings; `unionRect` of both is the natural "region the mark
  explains" for FR-003, and it is the same technique mark 1 and 2 use (a region, not a point).

**Alternatives rejected**:
- *Anchor by button text* — brittle against the "Validating…" state and any future copy pass.
- *Wrap the buttons in a new span to anchor* — extra markup for zero information; the union of
  the two existing elements is the region.

---

## R-4 The top bar still fits at 1440 px

**Decision**: a secondary **Tour** button before *Help* on the Flows screen; the flexible flow
name field absorbs the width.

**Findings**:
- `us21-getting-started.spec.ts:183-200` already asserts zero clipped controls and zero
  overflow at 1440 px, and it queries **every** `button, input` in the bar — the Tour button
  is covered by the existing check with no test edit.
- The bar's own CSS makes room before anything clips: the name field is `flex: 0 1 240px;
  min-width: 72px` and the name input `flex: 1 1 auto; min-width: 0`
  (`TopBar.svelte:213-229, 258-277`); spec 009 already used that flexibility for a fifth tab,
  and spec 010 for *Help*.
- A four-character secondary button is the width class of the existing *Save flow* button
  (padding `7px 10px`, `--size-body`): roughly 50–60 px. The name field gives up to ~170 px
  before reaching its minimum.

**Alternatives rejected**:
- *Put the tour inside the Help menu* — two actions, and spec FR-001 requires a visible
  one-action control; also the menu is on every screen while the tour is Flows-only.

---

## R-5 The four ways the canvas stops being editable (FR-011)

**Decision**: one `$effect` closes the tour on any of the four transitions; `signOut()` closes
it too.

**Findings** (from `+page.svelte`):
- `phase` is `{name:'idle'} | {'loading'} | {'ready'} | {'failed', message}` (line 38) —
  anything but `ready` is not an editable canvas.
- The run view replaces the whole app when `watching !== null` (lines 499-513) — the Flows
  branch does not render at all.
- The other screens (`overview`, `catalog`, `targets`, `runs`) render their own branches
  (lines 407-498).
- A mid-session expiry draws the sign-in overlay over the app while `phase` stays `ready`
  (lines 427-429 etc.) — so `session.status === 'expired'` must be its own close condition,
  or the tour would float above the overlay (native dialog = top layer).
- `signOut()` already closes the guide the same way (lines 396-401); the tour joins it.

**Alternatives rejected**:
- *Close only on unmount of the Flows branch* — misses the expiry overlay, which keeps the
  branch mounted; the explicit four-condition rule is one readable effect.

---

## R-6 No third-party tour engine

**Decision**: ~150 lines of owned code (`Tour.svelte` + `anchor.ts` + `tour.svelte.ts`).

**Rationale**: `driver.js`, `shepherd.js` and `intro.js` each bring their own positioning
engine, stylesheet and accessibility model that would have to be re-skinned onto the token
system (`lib/design`), add tens of KB to a bundle IRIS serves from disk, and move the a11y
contract (focus, *Escape*, dialog semantics) into a dependency right after this app proved its
own native-dialog primitives (R-2). For three fixed marks with no popovers-behaviour, the
engine is the part a library would rent us that we do not need.

**Alternatives rejected**: all three libraries, on weight, styling control and the closed
dependency set this repo keeps (`module.xml`, no runtime-extensible UI).

---

## R-7 E2e impact: none on the existing suite

**Findings**:
- File numbers `us1`–`us29` are taken (with `us22`, `us23`, `us29` each used twice by earlier
  features); **us30** is the next free number → `tests/us30-first-time-tour.spec.ts`.
- `support.ts` seeds `sentai.guide.dismissed` so the *guide* never covers a test
  (`support.ts:10-52`); the tour needs no seed because it never opens by itself
  (R-1). No existing spec file is edited: the guide's auto-open behaviour is unchanged
  (SC-002 is exactly "us21 still green").
- The theming helper `contrastFailures` (`tests/theming.ts`) works on any visible text, so the
  card is checked the same way us21 checks the guide's dialog.
- Evidence (PNG/JSON via `envelope`) goes to `specs/021-first-time-tour/evidence/`, and e2e
  drives the **baked** bundle — `bash scripts/publish-canvas.sh` before the run, as AGENTS.md
  requires.

---

## R-8 No scroll to follow

**Decision**: recompute the spotlight/card on step change and on window resize (listener only
while open); no scroll listener.

**Findings**: the app is a fixed full-viewport layout — `.app { display:flex; flex-direction:
column; height: 100% }` (`+page.svelte:601-605`), `.workspace { flex-grow:1; min-height:0 }`
(607-611) — with no page scrolling; the palette is a column and the canvas pans internally
(SvelteFlow), which does not move the anchor elements' viewport rects. Only a window resize
changes them.

**Alternatives rejected**: *follow `scroll` events or a `ResizeObserver` per anchor* — YAGNI;
nothing scrolls the anchors.

---

## R-9 Focus handling: extract, don't duplicate

**Decision**: move `Modal.svelte`'s Tab-wrap block (`Modal.svelte:36-53`) into
`shell/dialog-focus.ts` as `wrapTab(dialog, event)`; `Modal` and `Tour` both use it.

**Rationale**: the tour needs byte-for-byte the same rule (Tab wraps inside the open dialog).
Duplicating it would give the rule two owners; extracting keeps `Modal.svelte`'s behaviour
identical (`us21`'s keyboard test re-proves it) and gives the tour the same proven behaviour
for free.

**Alternatives rejected**: *copy the 15 lines into `Tour.svelte`* — two copies of an a11y rule
is exactly the "one reason to change" failure SoC exists for.
