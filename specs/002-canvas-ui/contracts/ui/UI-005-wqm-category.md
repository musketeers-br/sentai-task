# UI-005 · WQM category

**Image**: [`../screens/WQM.png`](../screens/WQM.png) · **Viewport** 1100×1000 · **Theme** light
**Route**: `/wqm/[category]` · **Covers**: FR-015 … FR-017, Constitution IV, VII

Five fields. The screen's whole job is making the *effect* of each one legible, because
the names are already familiar and the interaction between them is not.

---

## Structure

| Region | Contents |
|---|---|
| Header | `WORK QUEUE MANAGER · CATEGORY`, category name, class + scope line, host card |
| Nesting diagram | Four bars showing how the ceilings contain each other |
| Field list | One row per field: label + input, then effect, then consequence |
| Impact notice | How many other tasks the change affects |
| Actions | *Save category*, *Discard*, required privilege |

The host card (`iris-prod-01 · 16 cores`) is required: every ceiling is meaningless
without the core count to judge it against.

## The nesting diagram *(FR-016)*

Four horizontal bars sharing one track width, drawn in descending order:

| Bar | Fill | Width |
|---|---|---|
| `MaxTotalWorkers` | hatched, neutral | 100 % of the track |
| `MaxWorkers` | solid, muted | proportional to `MaxTotalWorkers` |
| `MaxActiveWorkers` | solid, accent | proportional to `MaxTotalWorkers` |
| `DefaultWorkers` | solid, ink | proportional to `MaxTotalWorkers` |

Each bar is labelled left and carries its value right, in tabular figures. Beneath, one
sentence reads the current configuration back against the actual flow:

> Each bar is a ceiling on the one above it. Under this category, 3 parallel integrity
> checks ask for 4 workers each — 12 in total, within MaxWorkers, but only 8 run at the
> same time.

That sentence recomputes when any field changes *(scenario 10)*. It is the screen's
single most important element: it turns four integers into a prediction.

The diagram also draws the invariant
`defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`. Violating it is a
validation **error**, not a warning.

## Field rows

Each row is a 210 px label column and an explanation column. The explanation is two
paragraphs, in this order and with this distinction:

1. **What it is** — body weight, full colour. One sentence, mechanical.
2. **What raising or lowering it costs** — muted, smaller. The trade-off, in operational
   terms.

Bound content, condensed:

| Field | What it is | The trade-off |
|---|---|---|
| `DefaultWorkers` | Workers a step asks for when it specifies nothing | Faster per step, more competition inside the wave |
| `MaxActiveWorkers` | Ceiling on workers *executing* at once; the rest stay allocated but waiting | The real CPU and disk pressure control |
| `MaxWorkers` | Ceiling on what one step can request, even asking for more | Protects against one misconfigured step taking the category |
| `MaxTotalWorkers` | Combined ceiling for the whole category at once | Below the sum of requests, excess steps queue rather than being refused |
| `AlwaysQueue` | Work always goes through the queue, even with a free worker | On, every step gets distinct `TimeQueued`/`TimeStarted` — which is what keeps UI-004 auditable |

The `AlwaysQueue` note is not incidental: turning it off makes short steps vanish from
queue accounting and silently degrades the run history. The screen says so.

Field names are IRIS's, unchanged *(Constitution IV)*. No "intensity", no "speed", no
slider that collapses several into one.

## Impact notice *(FR-017)*

Above the actions, in the warning token:

> Changing this category affects 7 scheduled tasks beyond this wave. The change takes
> effect on the next dispatch — runs in flight keep the ceilings they started with.

The count is computed, not decorative. Both halves are required: scope, then timing.

## Actions

*Save category* (primary) and *Discard*. Right-aligned beside them, the privilege the
operation requires: `requires %Admin_Task:USE`.

## Vocabulary — verbatim strings

`WORK QUEUE MANAGER · CATEGORY` · `%SYSTEM.WorkMgr · applied to every step of the
maintenance wave` · `HOST` · `HOW THE CEILINGS NEST` · `DefaultWorkers` ·
`MaxActiveWorkers` · `MaxWorkers` · `MaxTotalWorkers` · `AlwaysQueue` · `On` ·
`Save category` · `Discard` · `requires %Admin_Task:USE`

## Not bound

Field order in the list (the diagram's descending order is bound; the list's ascending
order is a reading choice). The exact wording of the two explanation paragraphs, as long
as the distinction between *what it is* and *what it costs* survives.

## Acceptance

Scenario 10 of `spec.md`. The visual test asserts: four bars in descending order with
proportional widths; the recomputed sentence updates on a field change; the invariant
produces an error, not a warning, when violated; the impact notice states both a count
and the in-flight rule.
