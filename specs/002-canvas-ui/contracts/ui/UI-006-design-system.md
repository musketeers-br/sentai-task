# UI-006 · Design system

**Image**: [`../screens/System.png`](../screens/System.png) · **Viewport** 1100×880 · **Theme** both
**Covers**: FR-020, FR-037, FR-038, Constitution II, VI, VII

**This contract is normative.** Where any other screen disagrees with this one about a
state shape, an edge treatment or a token value, this one wins and the other screen is
the defect.

Machine-readable companion: [`../tokens.json`](../tokens.json).

---

## The mark

Five bars — red, blue, yellow, green, pink — at heights 20/16/12/16/20, 4 px wide, 2 px
apart, followed by `SENTAI` in the display face at 700 and `TASK` at 500 in the muted
token.

The mark is the product's only brand element and it is **not an accent**. There is no
single brand colour. Those five hues appear in exactly two places: this mark, and the
step-type category swatches in the palette. They never encode state.

This is what satisfies "semantic colour separate from accent" without leaving the product
colourless: the identity is a multi-colour bar, so no hue is spent on branding that state
needs.

## Job states — shape first, colour second *(Constitution II)*

Six states. The **shape** is the contract. The colour is a token and may be re-valued per
theme; the shape may not change at all.

| State | Shape | Drawn as |
|---|---|---|
| `queued` | dashed hollow square | `<rect>` no fill, 1.4 stroke, dasharray 2.6 2 |
| `running` | pointing triangle | filled `<path>`, apex right |
| `paused` | two vertical bars | two filled `<rect>`, equal width, centre gap |
| `completed` | filled circle with a check | `<circle>` filled + check stroked in the surface colour |
| `failed` | filled warning triangle | filled `<path>`, apex up, with `!` knocked out |
| `cancelled` | slashed circle | `<circle>` no fill + diagonal stroke |

Rules:

- These six SVG primitives live in **one** component (`StateShape.svelte`). No screen
  draws its own.
- Every surface showing a state shows the shape. Colour may accompany it; colour alone
  never carries it.
- The set is closed. A seventh state requires a constitutional amendment.
- Rendered at 11–14 px in chips and table rows, 26 px in the key. The shapes are chosen
  to survive 11 px: no shape depends on an interior detail smaller than 2 px.

Verification: render each shape at 11 px, desaturate to greyscale, and confirm all six
remain mutually distinguishable. That test ships.

## Destructive marking *(Constitution I)*

Three signals, all required, shown together on this sheet:

1. **Hazard band** — 6 px, 45° stripes alternating the destructive token and the node
   surface, across the node's top edge.
2. **Text seal** — `DESTRUCTIVE`, monospace, uppercase, 0.08 em tracking, warning
   triangle, in a bordered chip.
3. **Typed confirmation** — the database or namespace name, typed by the operator, before
   dispatch.

The sheet states the rule in words beside the example: *“Three signals stacked: hazard
band across the top of the node, a text seal, and typed confirmation before dispatch.
Never colour alone.”*

## Themes *(Constitution VI)*

Two ramps, authored independently, shown side by side so the independence is auditable.

**Dark** — ground `#0A0D13`, card `#141A26`, border `#2B3648`, text `#E6EBF2`.
Ink-blue ground at low overall luminance; cards sit **above** the ground; no pure black,
which glares against white text in a dim room for an hour at a stretch.

**Light** — ground `#EFEDE7`, card `#FFFFFF`, border `#C9C3B6`, text `#16181D`.
Warm paper with white cards; the elevation model **inverts** — in dark the card rises,
in light it lightens against paper — and a 1 px shadow replaces the dark theme's
selection halo.

No token's value in one theme is computed from its value in the other. `tokens.json`
carries both explicitly.

## Typography *(Constitution VII)*

| Face | Role | Used for |
|---|---|---|
| **Chakra Petch** 500/600/700 | display | Section labels, the wordmark, small-caps headers |
| **IBM Plex Sans** 400/500/600/700 | UI | Body, labels, buttons, table names |
| **IBM Plex Mono** 400/500/600 | mono | All numerals, durations, GUIDs, namespaces, class names, paths |

`font-variant-numeric: tabular-nums` is set globally and MUST NOT be overridden. Every
figure in a column aligns digit under digit.

Chakra Petch is confined to labels and the mark. It never sets body text, and it never
sets a number.

## Edges and handles

| Element | Spec |
|---|---|
| Sequence edge | 1.5 px, muted token, arrowhead |
| Join edge | 2.5 px, strong token, shared diamond junction |
| Plain handle | 8 px square, 1.5 px border, 2 px radius |
| Join handle | 10 px diamond (45°-rotated square), 2 px border |

The diamond means "join" everywhere it appears — canvas junction, join target handle,
and the join marker on the run timeline.

## Accessibility floor

- Text contrast ≥4.5:1, or ≥3:1 at ≥24 px, **in both themes**. Muted caption greys and
  coloured fills under light text are where this usually fails; both were darkened.
- Real semantic elements: `<button>`, `<a href>`, `<input>` + `<label>`. Never `role` or
  a click handler on a `div`.
- Icon-only controls carry `aria-label`.
- No emoji as a UI glyph, anywhere.
- Visible focus ring in both themes, on every interactive element.

## Acceptance

The visual test for this screen asserts the six shapes render as specified, the
greyscale-distinguishability check passes, and both theme ramps are present with the
documented values.
