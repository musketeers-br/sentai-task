# UI-002 · Live run

**Image**: [`../screens/LiveRun.png`](../screens/LiveRun.png) · **Viewport** 1440×900 · **Theme** dark
**Route**: `/runs/[guid]` · **Covers**: FR-018 … FR-027, Constitution I, II, III

The same graph as UI-001, executing. This is the screen an operator stares at in a
maintenance window, so every decision it supports — let it continue, kill this step, kill
the wave — must be answerable without scrolling or clicking.

---

## Structure

| Region | Size | Contents |
|---|---|---|
| Top bar | 52 | Mark, `RUN IN PROGRESS` pill, flow name, short run GUID, *Pause wave*, *Cancel wave* |
| Wave progress | 54 | Segmented bar, state counts, elapsed, start time |
| Canvas | fills | The graph with live state per node, join policy note, minimap |
| Right rail | 348 | Run GUID, per-step list, state key, run log |

The wave progress strip sits between the top bar and the canvas, full width. It is the
one thing readable from across a room.

## Wave progress *(FR-026)*

One segment per step, in flow order, equal width, 8 px tall, 3 px gaps. Each segment's
fill encodes its step's state, and the running segment fills proportionally to progress.
The failed segment uses the hazard stripe pattern so it reads as failed in a monochrome
screenshot.

Beside it, the count line, verbatim format:
`2 completed · 1 failed · 1 running · 1 queued`

Right of it: `ELAPSED` over a monospace `00:24:17`, and `START` over `03:00:02`.

## Node states *(FR-019, FR-020)*

Every node carries a state chip: shape glyph + uppercase monospace state name, in a
bordered chip. The shape is normative (UI-006); the chip's border and text colours are
tokens.

The image shows four of the six states live:

| Node | State | What the node must show |
|---|---|---|
| #01 Integrity check — USER | `COMPLETED` | duration `12:04.7`, abbreviated GUID |
| #02 Integrity check — SAMPLES | `COMPLETED` | duration `08:51.2`, abbreviated GUID |
| #03 Integrity check — DOCBOOK | `FAILED` | `FAILURE REASON` panel, time of failure, *Re-run step* |
| #04 Purge audit records | `RUNNING` | elapsed, progress bar + counts, GUID, *Pause* + *Cancel* |
| #05 Switch journal | `QUEUED` | dashed border, what it waits for, queued-since |

`paused` and `cancelled` appear in the state key; they are not exercised by this example
run. The implementation must render all six.

## Failed node *(FR-022)*

The `FAILURE REASON` panel shows the string **verbatim** as IRIS produced it:

```
ERROR #5002: ObjectScript error <PROTECT>zCheck+18 — database mounted read-only
```

Not summarised, not sentence-cased, not truncated with an ellipsis at the panel edge. If
it is longer than the panel, the panel scrolls or expands. A *Re-run step* action sits in
the node.

The edge leaving a failed node renders dashed in the failure token, so the break in the
wave is visible at zoom-out.

## Running node *(FR-021, FR-024)*

- Elapsed time in the largest monospace on the node: `06:41.8`.
- Progress, where the type reports it: a bar plus the literal counts
  (`1,284,009 of ~2.1 M records`). Where the type reports none, the bar is absent —
  never a fake indeterminate animation.
- Its GUID, abbreviated, with the full value one click away *(Constitution III)*.
- **Per-step** *Pause* and *Cancel*, inside the node. Cancelling here cancels this step
  only *(scenario 7)*.
- The node keeps its hazard band: a destructive step is still destructive while running.

## Join policy *(FR-025)*

Because an input failed, the policy in force is stated on the canvas, near the join:

```
JOIN POLICY
Proceed on partial failure — 2 of 3 completed meets the minimum
```

This panel is **required whenever any join input has failed**. Without it the operator
cannot tell whether the wave is proceeding correctly or running away.

## Right rail

Four blocks, in order:

1. `RUN GUIDS` — the full run GUID, selectable, never truncated.
2. Per-step list — shape glyph, `#NN` + name, duration right-aligned in tabular figures.
   The running step is bold. A queued step shows `—`.
3. `STATES — SHAPE BEFORE COLOUR` — the six-state key, always visible. It is a
   permanent legend, not a tooltip *(Constitution II)*.
4. `RUN LOG` — newest first, monospace, one line per event, timestamped. Destructive
   confirmations are logged with the confirming user *(FR-013, FR-027)*.

## Wave-level controls

*Pause wave* and *Cancel wave* in the top bar. *Cancel wave* is styled in the destructive
token and MUST require confirmation naming the run. It stops dispatch of anything not yet
started and requests cancellation of what is running.

## Vocabulary — verbatim strings

`RUN IN PROGRESS` · `Pause wave` · `Cancel wave` · `WAVE PROGRESS` · `ELAPSED` ·
`START` · `COMPLETED` · `RUNNING` · `QUEUED` · `FAILED` · `PAUSED` · `CANCELLED` ·
`DESTRUCTIVE` · `FAILURE REASON` · `Re-run step` · `Pause` · `Cancel` ·
`JOIN POLICY` · `RUN GUIDS` · `STATES — SHAPE BEFORE COLOUR` · `RUN LOG` ·
`waits for #04` · `queued since 03:00:02`

## Not bound

Node positions (inherited from the flow's saved geometry). Run-log depth. Whether the
rail is resizable.

## Acceptance

Scenarios 6 and 7 of `spec.md`, plus NFR-001. The visual test asserts all six state
shapes are reachable, that the failure reason renders untruncated, and that the join
policy panel appears when an input has failed.
