# Data Model: First-Time Canvas Tour — Three Coach Marks

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Research**: [research.md](research.md)

No persisted entity of any kind: nothing is stored, cached or sent (spec FR-010). The model
below is one fixed data constant, one state machine, and one pure geometry module.

---

## 1. Tour mark (fixed data)

Module: `frontend/src/lib/tour/steps.ts` (pure). Exactly three instances, declared in the
codebase; nothing comes from user input (Constitution II).

| Field | Type | Rule |
|---|---|---|
| `key` | `'palette' \| 'connections' \| 'validate-run'` | position and identity in the order; `TOUR_STEPS[i].key` is the contract name used by tests and [contracts/tour.md](contracts/tour.md) |
| `anchor` | readonly selector list | at least one; resolved by the component, never by the data ([§3](#3-anchor-geometry-pure)) |
| `body` | English text | conveys the spec's required content for that mark (FR-002); suggested copy is normative content, final wording per Plan |

| # | key | body | anchor selectors |
|---|---|---|---|
| 1 | `palette` | "This is the palette — drag a step onto the canvas." | `aside[aria-label="Step types"]` |
| 2 | `connections` | "Connect two steps to create a dependency." | `.canvas[role="application"]` |
| 3 | `validate-run` | "Validate the flow, then run it." | `[data-tour-target="validate"]`, `[data-tour-target="run"]` |

Validation (unit-tested in `steps.test.ts`): exactly 3; order `palette → connections →
validate-run`; every selector matches its contract entry; body non-empty.

## 2. Tour state machine (no persistence)

Module: `frontend/src/lib/tour/tour.svelte.ts` (runes), singleton `tour` (the `theme.svelte.ts`
pattern). There is no preference module and no storage: every launch is identical (FR-010).

```text
                 start()                 next()              next()
   ┌────────┐  ────────────────▶  ┌────────┐  ──────▶  ┌────────┐  ──────▶  ┌────────┐
   │ closed │                    │ mark 1 │          │ mark 2 │          │ mark 3 │
   └────────┘  ◀────────────────  └────────┘  ◀──────  └────────┘  ◀──────  └────────┘
     ▲  ▲        skip() / close()      (next() on mark 3 clamps; Done = finish())
     │  │
     │  └── skip() from any mark; Escape (native cancel) routes to skip()
     └──── finish() from mark 3; close() from the page's close rule
```

| Member | Kind | Rule |
|---|---|---|
| `open` | `$state<boolean>` | the dialog renders while true |
| `step` | `$state<number>` | 1-based, in `1…3`; `start()` always resets it to 1 (FR-010: identical every launch) |
| `steps` | readonly | `TOUR_STEPS` |
| `start()` | transition | `open = true; step = 1` — the only public entry (FR-001); no preconditions |
| `next()` | transition | `step = min(step + 1, 3)`; never wraps, never opens |
| `skip()` | transition | `open = false` — from any mark (FR-005); the *Escape* path |
| `finish()` | transition | `open = false` — the *Done* control on mark 3 |
| `close()` | transition | `open = false` — idempotent; the page's close-rule call (FR-011) |

There are no other events. `skip()`, `finish()` and `close()` are the same transition with
different callers, so none can diverge.

## 3. Anchor geometry (pure)

Module: `frontend/src/lib/tour/anchor.ts` (pure, unit-tested). `Rect` and `Point` are plain
objects; **only the component** converts `getBoundingClientRect()` results into them (the DOM
edge, Principle I).

| Operation | Signature | Rule |
|---|---|---|
| `unionRect` | `(rects: Rect[]) → Rect \| null` | the bounding box of all rects; `[]` (a selector that no longer matches — [research R-3](research.md)) → **`null`, never a throw** (Constitution IV): the component renders a centered card with no spotlight |
| `pad` | `(rect, inset) → Rect` | the spotlight hole is the anchor rect grown by 8 px |
| `placeCard` | `(target: Rect, viewport: Size, card: Size) → Point` | prefer 12 px below the target; if the card would pass the viewport bottom, place it 12 px above the target's top; clamp x so the card always keeps ≥ 12 px inside the viewport — a target wider than the viewport still yields an on-screen card (spec edge case) |

Recomputed on `step` change and on window resize (listener registered only while `open`);
there is no scroll to follow ([research R-8](research.md)).

## 4. Dialog semantics (FR-004, FR-005, FR-006)

`Tour.svelte` renders one native `<dialog>` shown with `showModal()`:

- accessible name **"Tour"** via `aria-labelledby` → the card's `h2` (`data-testid`-free; the
  e2e targets `getByRole('dialog', { name: 'Tour' })`);
- the mark message is `aria-describedby` → `p[data-testid="tour-mark-body"]`;
- the position indicator ("1 of 3") is `p[data-testid="tour-indicator"]`, `aria-live="polite"`;
- controls: *Skip* (quiet, every mark), *Next* (primary, marks 1–2), *Done* (primary, mark 3);
- focus starts on the card heading (`tabindex="-1"` + autofocus, the guide's pattern); *Tab*
  wraps inside via `shell/dialog-focus.ts` — extracted from `Modal.svelte`, which keeps the
  same behaviour ([research R-9](research.md)); *Escape* fires native `cancel` → `skip()`;
  on any close, focus returns to the element that had it — the **Tour** button.

## 5. Integration points (the only wiring)

| Point | Change | Rule |
|---|---|---|
| `TopBar.svelte` | a secondary **Tour** button (`data-testid="tour-button"`), rendered only when `screen === 'flows'`, before the *Help* menu; new `ontour` prop; `data-tour-target` on *Validate flow* / *Run now* | FR-001; the bar still fits at 1440 px ([research R-4](research.md)) |
| `+page.svelte` (Flows branch) | `ontour={() => tour.start()}`; render `<Tour />` beside the other dialogs | the only entry (FR-009) |
| `+page.svelte` (close rule) | `$effect`: `phase.name !== 'ready' \|\| screen !== 'flows' \|\| watching !== null \|\| session.status === 'expired'` → `tour.close()`; `signOut()` calls it too | FR-011 — the four ways the canvas stops being editable ([research R-5](research.md)) |
| spec 010 guide | **none** — `guide.*`, `shouldAutoOpen`, `preference.ts`, Help menu untouched | FR-008, SC-002 |

Nothing else in the tree changes: no `fetch`, no storage key, no backend module.
