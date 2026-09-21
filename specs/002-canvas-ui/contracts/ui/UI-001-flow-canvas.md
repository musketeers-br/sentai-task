# UI-001 · Flow Canvas

**Image**: [`../screens/Main.png`](../screens/Main.png) · **Viewport** 1440×900 · **Theme** dark (default)
**Route**: `/flows/[id]` · **Covers**: FR-001 … FR-011, Constitution I, II, IV, VI, VII

The hero screen. Everything else in the product exists to serve what is composed here.

---

## Structure

Four fixed regions plus the canvas. Left-to-right, top-to-bottom:

| Region | Size | Fixed? | Contents |
|---|---|---|---|
| Top bar | height 52 | fixed | Mark, namespace chip, flow name, revision+save time, theme switch, *Validate flow*, *Schedule in Task Manager* |
| Step palette | width 248 | fixed, scrolls internally | Search field, then categories, each a colour swatch + label + its step types |
| Canvas | fills | pan/zoom | Nodes, edges, edge legend, zoom controls, minimap |
| Inspector | width 320 | fixed, scrolls internally | Selected step: identification, parameters, destructive block, output |
| Status bar | height 32 | fixed | Step/join/destructive counts, warning count, snap, zoom |

The palette is left and the inspector right. Swapping them, or collapsing either into a
drawer, is a contract change.

## The graph shown

Five steps, named exactly:

```
#01 Integrity check — USER      ┐
#02 Integrity check — SAMPLES   ├─fan-in─► #04 Purge audit records ──► #05 Switch journal
#03 Integrity check — DOCBOOK   ┘
```

This is the canonical example. The implementation renders whatever graph the operator
built; the contract is that a 3-into-1 fan-in followed by a sequence edge renders as
shown.

## Edges *(FR-004)*

| | Sequence | Fan-in (join) |
|---|---|---|
| Stroke width | 1.5 | 2.5 |
| Colour token | `edge.sequence` | `edge.join` |
| Terminator | arrowhead | shared diamond junction, then one arrow into the target |
| Target handle | square | **diamond**, 2 px stroke |

The junction diamond is drawn **once per target**, not once per incoming edge. Three
incoming edges converge into one diamond. A legend in the canvas top-left states both
edge kinds; it is part of the contract, not decoration.

## Handles

Small squares on the node's left (input) and right (output) edges, vertically centred on
the node's title row. Connected handles render with the stronger border token,
unconnected with the muted one. A join target's input handle is the diamond described
above.

## Node anatomy

```
┌─ hazard band (destructive only, 6px, 45° stripes) ─────────┐
│ Title                                            #NN       │
│ [namespace chip]  namespace                                │
│ /database/directory/                                       │
│ ─────────────────────────────────────────────────────────  │
│ timeout N min                        wqm: N workers        │
└────────────────────────────────────────────────────────────┘
```

Left border, 3 px, carries the **step-type category colour** — never a state colour
*(Constitution II)*. Node #04 in the image is selected: 1 px accent border plus a 3 px
offset ring.

## Precondition warning *(FR-008)*

Node #03 shows the warning state. It is three things together:

1. The node border switches to the warning token.
2. An inset panel inside the node: warning triangle, bold title
   **“Precondition not met”**, then the condition in plain words — here
   *“Database mounted read-only. Integrity check requires write access to the directory.”*
3. The status bar counts it: `1 precondition not met (#03)`.

A warning does not block scheduling *(FR-010)*. The wording names the condition and what
the step needs — never a bare “invalid”.

## Destructive marking *(Constitution I — mandatory, all three)*

Node #04 carries all of:

1. **Hazard band** — 6 px, 45° stripes in the destructive token, across the node's top.
2. **Text seal** — `DESTRUCTIVE`, monospace, uppercase, with a warning triangle, inside a
   bordered chip.
3. **Typed confirmation** — the inspector's destructive block holds a checked control
   *“Require the database name to be typed before running”*, with the consequence spelled
   out above it: *“Permanently removes audit records older than 30 days. There is no
   rollback: it requires a valid backup taken today.”*

The palette entry for a destructive step type carries a miniature hazard swatch, so the
marking is visible before the step is even placed.

None of the three may be dropped at any zoom level or in any density mode.

## Inspector

Sections in this order, labelled exactly:

`SELECTED STEP` → `IDENTIFICATION` (TaskName, Namespace, Run as user) → `PARAMETERS`
(type-specific, then Timeout (min), then WQM category) → destructive block, if any →
`OUTPUT`.

`OUTPUT` shows where the step's GUID lands: `step04.guid → ^SentaiRun(runId,"04")`
*(Constitution III)*.

Every field is a real `<input>` with a real `<label>`. No `div` with `role`.

## Canvas furniture

- **Zoom controls**, bottom-left, vertical: zoom in, zoom out, fit view, lock. Icon-only
  buttons carry `aria-label`. No emoji glyphs.
- **Minimap**, bottom-right, 168×104: nodes as blocks in their step-type category colour,
  viewport as an outlined rectangle.
- **Dot grid**, 16 px, in the canvas background only.

## Vocabulary — verbatim strings

Top bar: `Validate flow` · `Schedule in Task Manager` · `Dark` · `Light`
Palette: `STEP TYPES` · `VERIFICATION` · `STORAGE` · `JOURNAL` · `PURGE` · `CUSTOM`
Class names shown under each entry: `%SYS.Task.IntegrityCheck`,
`%SYS.Task.CompactGlobals`, `%SYS.Task.Defragment`, `%SYS.Task.SwitchJournal`,
`%SYS.Task.PurgeAuditDB`, `%SYS.Task.PurgeTaskHistory`,
`subclass of %SYS.Task.Definition`
Inspector: `SELECTED STEP` · `IDENTIFICATION` · `TaskName` · `Namespace` ·
`Run as user` · `PARAMETERS` · `DaysToKeep` · `Timeout (min)` · `WQM category` ·
`DESTRUCTIVE STEP` · `OUTPUT`
Canvas: `sequence` · `join (fan-in)` · `join: waits for #01 #02 #03`
Status bar: `5 steps · 1 join · 1 destructive` · `1 precondition not met (#03)` ·
`snap 8 px` · `zoom 100%`

## Not bound

Node width (240 in the image) may adapt to content. Palette category order may follow a
configured preference. The dot-grid spacing is a token.

## Acceptance

Scenarios 1–5 of `spec.md`. The visual test additionally asserts: the fan-in edge's
stroke width differs from the sequence edge's; the destructive node carries all three
signals; `#03` renders the warning panel with its condition text.
