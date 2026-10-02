# UI Contract: The Tour (button, marks, anchors)

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Data model**: [data-model.md](data-model.md)

The tour changes no wire contract: no HTTP endpoint, no request or response shape, no
ObjectScript. This document is the contract the three marks, the component and the e2e
(`tests/us30-first-time-tour.spec.ts`) share — the UI equivalent of an API schema. Breaking a
row below is a contract break, reviewable as one.

## 1. Entry — the button (FR-001)

| Property | Value |
|---|---|
| Visible on | the Flows screen only (`screen === 'flows'`, not watching a run) |
| Label | `Tour` |
| Test id | `data-testid="tour-button"` |
| Effect | `tour.start()` — one action, no preconditions, no dialog args |
| Not rendered | Overview, Task catalog, Targets, Runs, the run view, any non-`ready` phase |

## 2. The dialog (FR-002…FR-007)

| Property | Value |
|---|---|
| Role / name | `role="dialog"`, accessible name **"Tour"** (`aria-labelledby` → the card's `h2`) |
| Message | `p[data-testid="tour-mark-body"]`, `aria-describedby` |
| Position indicator | `p[data-testid="tour-indicator"]`, text `"{n} of 3"`, `aria-live="polite"` |
| Controls | *Skip* (every mark), *Next* (marks 1–2), *Done* (mark 3) |
| Spotlight | one element `data-testid="tour-spotlight"`, whose box is the anchor region grown by 8 px (rounded); mark 3's box covers **both** `validate` and `run` |
| Escape | native `cancel` → same as *Skip* |
| Focus | starts in the card; *Tab* wraps inside (`shell/dialog-focus.ts`); returns to the **Tour** button on close |
| Never | opens automatically (FR-009); persists anything (FR-010); renders over a sign-in, refusal or error state (FR-011) |

## 3. The anchor registry (FR-003)

| # | Mark key | Message (English, fixed) | Anchor selectors |
|---|---|---|---|
| 1 | `palette` | This is the palette — drag a step onto the canvas. | `aside[aria-label="Step types"]` |
| 2 | `connections` | Connect two steps to create a dependency. | `.canvas[role="application"]` |
| 3 | `validate-run` | Validate the flow, then run it. | `[data-tour-target="validate"]`, `[data-tour-target="run"]` |

- The selectors in rows 1–2 are existing stable attributes of `Palette.svelte` and
  `FlowCanvas.svelte`; row 3's attributes are added to the two `TopBar` buttons by this feature.
- A selector that matches nothing is a degraded value, not an error: the mark shows a centered
  card with no spotlight, and `us30` fails on the overlap assertion.
- The e2e asserts, per mark, that the spotlight box overlaps the anchor element's box — the
  contract's enforcement mechanism.

## 4. State transitions (FR-005, FR-010)

`start()` → mark 1; `next()` → +1 (max 3); *Done* or *Skip* or *Escape* → closed; the page's
close rule (phase not `ready`; screen not `flows`; `watching`; session `expired`) → closed.
Every launch is identical; nothing is remembered between launches.
