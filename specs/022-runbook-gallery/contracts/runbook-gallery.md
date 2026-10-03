# UI Contract — Runbook Gallery

**Feature**: [spec.md](spec.md) · **Data model**: [data-model.md](../data-model.md)

No wire contract is added or changed: the gallery uses the existing `GET/POST /flows`,
`GET /targets` and the step-type catalog exactly as shipped. This contract fixes the UI surface
the tests rely on, the way [specs/021's tour contract](../../021-first-time-tour/contracts/tour.md)
does for its anchors.

## Mount and visibility

- The gallery renders **only** in the Flows screen's editing state, at the invitation's old mount
  (inside `.canvas-area`, `+page.svelte`), when `unreadable === null && editor.id === null &&
  editor.steps.length === 0 && !galleryDismissed`.
- It never renders over the unreadable-flow panel, a refusal, an unreachable state or the
  sign-in overlay.
- The palette, the top-bar controls and the Tour button stay present around it (spec 021's
  anchors remain valid — FR-015).

## Test ids

| testid | Element | Contract |
|---|---|---|
| `runbook-gallery` | the gallery region (`role="region"`, accessible name "Runbooks") | attached iff visible; never over a platform state |
| `runbook-card` | one card | one per shipped runbook (7 at launch); carries `data-runbook="<slug>"` |
| `runbook-card-graph` | the card's mini-graph SVG | node/edge counts equal the definition's steps/edges |
| `runbook-card-cadence` | the suggested-cadence line | present iff the runbook declares one; text only |
| `runbook-card-use` | the card's Use button | enabled iff the verdict is runnable; verbatim refusal surfaces elsewhere (FR-009) |
| `runbook-card-reason` | the unavailability reason | present iff the verdict is unavailable |
| `start-from-scratch` | the blank-canvas button | always present in the gallery; sets `galleryDismissed` |

Slug rule: the `data-runbook` slug is the runbook's `flowName` lowercased with non-alphanumerics
collapsed to `-` (stable, derived, never localized) — e.g. `showcase-nightly-checks-across-servers`.

## Keyboard and announcement

- The gallery is a labelled region, not a modal: its cards and buttons are native elements in
  tab order; no focus trap, no `Escape` rule (dismissing is *Start from scratch*, a button).
- Each card's Use is reachable and activatable by keyboard alone (FR-016).
- All text in English (FR-017); the use control is labelled **Use**.

## Entry points (FR-013)

| Entry | Was | Now |
|---|---|---|
| Getting-started dialog, step 2 | "Open example flow" button → opens the single example | **Browse runbooks** → lands on the gallery (guard first when dirty); guide copy updated |
| *Open flow…* dialog | "Open example flow" button | **Browse runbooks** → same handler |
| Empty canvas (any instance, flows saved or not) | invitation (only when no flows) | the gallery (FR-001) |

The lone example retires into the seventh card: `Example: storage health check`.

## Use outcomes (observable contract)

1. Runnable card + Use → a flow of the runbook's `flowName` is open on the canvas, one action;
   a create goes through `POST /flows` with the operator's own sign-in.
2. Use again on the same card → the **same** flow (the name index decides; never a duplicate).
3. Dirty canvas + Use → the Save / Discard / Cancel guard first (unchanged copy).
4. Platform refusal during Use → the platform's status and reason surface as-is; nothing is
   created, nothing is retried.
5. Unavailable card (missing step type or target) → Use disabled, `runbook-card-reason` present.

## Superseded selectors (tests must not use them anymore)

`example-invitation`, the guide's `action: 'open-example'`, and any button labelled
"Open example flow" — replaced by the table above. The guarantees of `us20` move 1:1 to `us31`
(see plan *Testing Strategy*).

## Fixture sync (the contract behind the cards)

The example, weekly-window and cross-server card definitions equal
`tests/fixtures/{example-flow,weekly-window-flow,showcase-flow}.json`, which the ObjectScript
side also compares against its own definitions (`DemoTest`). Editing any of the three
definitions requires editing its fixture on both sides in the same change — the suites fail
otherwise.
