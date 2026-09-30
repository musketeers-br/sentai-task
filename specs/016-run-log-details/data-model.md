# Data Model: Flow Execution Log Detail

No new persisted entity. Everything below is a view model over the run read
(`GET /runs/{guid}`) as `fromWireRun` (`frontend/src/lib/run/run.ts`) adapts it. See
[contracts/run-view-delta.md](contracts/run-view-delta.md) for the wire shapes consumed.

## 1. Consumed wire shapes (unchanged)

**LogEntryWire** → `LogEntry` (exists): `at`, `stepId` (nullable), `severity` (`info` |
`warning` | `error`, anything else passed through), `message`. Read newest-first.

**StepRunWire** → `StepRunView` (extended): the existing fields plus:

| Field | Rule |
|---|---|
| `result` | `Record<string, unknown> \| null` — the served object; `{}` maps to `null` (no result). A stored truncation carries `truncated: true` and `omitted: <n>` **inside** the object; the view never adds or removes markers. |

`fromWireRun` keeps its existing latest-attempt-per-step rule: `steps[]` is the latest attempt of
each step, ordered by step id. The log slice (below) is what carries *every* attempt.

## 2. `stepdetail.ts` — the step execution detail

`buildStepDetail(step: StepRunView, flow: FlowDocument, nowMs: number): StepDetailView`

| Field | Source / rule |
|---|---|
| `stepId`, `taskName` | step id; the flow's step name (`#<id>` when unnamed) |
| `state` | `StepRunView.state` |
| `timeQueued`, `timeStarted`, `timeFinished` | verbatim; `—` when not yet known (FR-011: nothing invented) |
| `duration` | `stepDurationMs(step, nowMs)` — `null` before the step starts |
| `executedOn`, `executedAs` | as the run read says (`local` or a target name; who ran it) |
| `failureReason` | verbatim, whole, when `state === 'failed'` and the read carries one |
| `result` | `{ json: string; truncated: boolean; omitted: number \| null }` — pretty-printed stored object; `truncated`/`omitted` read from the object itself; `null` when there is no result |
| `logSlice` | `sliceFor(run.log, stepId)` — every attempt's entries, chronological (§3) |

Copy texts are built here, exactly as displayed: `copyText(detail)` (reason / result JSON blocks)
so tests compare one string against the wire (SC-002).

**Validation rules carried from the spec**: a not-yet-started step shows `—` for times, duration,
place and identity — never a plausible placeholder (FR-011); the result's truncation markers are
data shown to the operator, not errors (FR-009).

## 3. `logview.ts` — the log's display shape

| Function | Rule |
|---|---|
| `chronological(log)` | reverses the API's newest-first order → oldest first |
| `mergeLog(prev, next)` | entries already shown keep their first-seen order (stable key: `at \| stepId \| message` + first-seen sequence); unseen entries append at the chronological end; returns the same objects when unchanged (referential stability for keyed rendering) |
| `sliceFor(log, stepId)` | only entries whose `stepId` equals `stepId`, chronological — run-level entries (no step) are excluded from slices |
| `severityLabel(severity)` | `info`→`INFO`, `warning`→`WARN`, `error`→`ERROR`; an unknown severity passes through uppercased, never dropped (FR: edge case) |
| `narrow(entries, {severity?, stepId?})` *(increment 3)* | severity and step compose; `null` filters mean "all" |
| `counts(entries, filters)` *(increment 3)* | `{ shown, total }` → "N of M" |

## 4. Screen state (nothing persisted)

| State | Owner | Notes |
|---|---|---|
| `selectedStepId: string \| null` | `RunMonitor` (run context) | addressed as `?run=<guid>&step=<id>`; clicking a node or row selects, the detail's close affordance deselects; the log panel follows the selection (slice) |
| follow flag | log panel | derived: operator is at the bottom ⇒ follow the newest; scrolled up ⇒ preserve position, show *Jump to latest* |
| severity narrowing | log panel | screen-only; not addressed (US3 is P2) |

## 5. Address contract

`?run=<guid>` opens the run view (today). `?run=<guid>&step=<stepId>` additionally selects the
step. Rules: `step` naming a step the flow does not have deselects silently (the run view's flow
snapshot is the authority); an absent `step` shows the unselected run view. Selection changes
rewrite the address with `replaceState` (the catalog's `task` precedent), so back/forward move
through selections without stacking a history entry per click.
