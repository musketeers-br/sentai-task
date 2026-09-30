# Research: Flow Execution Log Detail

## R-1 What the run read already carries (backend work: none)

- `GET /runs/{guid}` serializes each step via `ShapeStepRun` (`src/sentai/rest/Dispatcher.cls`):
  `state`, `timeQueued`, `timeStarted`, `timeFinished`, `failureReason`, `progressCurrent/Total`,
  `executedAs`, `executedOn` (`"local"` default) and **`result`** — the stored JSON parsed, `{}`
  when absent or invalid. `log` is an array of `{at, stepId, severity, message}`, newest first.
- The frontend's `fromWireRun` (`run.ts`) maps everything **except `result`** — the result is
  dropped on the floor today; no screen shows it.
- The openapi `StepRun` schema documents none of `result` / `executedOn` / `executedAs`, though
  all three are served (added by specs 005/008 without the doc).
- **Decision**: 016 is pure frontend. The only backend-adjacent change is documenting the three
  served fields in `specs/002-canvas-ui/contracts/openapi.yaml` — additive, doc-only. No new
  endpoint, no new query parameter, no serializer change.

## R-2 The collision with spec 012 (in parallel development)

- 012's plan creates `frontend/src/lib/run/log.ts`, e2e specs `us24`–`us26`, and its increment 2
  is the same log panel (chronological, text severity labels, empty-log wording, scroll-to-end
  while live). 012 also owns the *Runs* screen and export.
- **Decision**: 016 consumes 012's territory, it does not rebuild it. Concretely: the pure module
  is named `logview.ts` (not 012's `log.ts`); e2e specs start at `us27`; 016's panel work is
  scoped to the spec's contract (labels beyond colour, copy, jump-to-latest, scroll preservation,
  wrap guarantees, slice) and **skips anything 012 has already delivered** when its panel lands
  first. The shared surface is `RunScreen.svelte`'s log section — the one coordination point;
  both teams must expect a merge there. Until 012's recording lands, the panel shows honest empty
  text and every affordance is tested with whatever entries exist — which is why the MVP
  (increment 1) reads only step fields and has **zero** dependency on 012.

## R-3 Entry order stability across polls

- The log read orders by `at DESC` with **no tiebreak**, and `at` has second precision today
  (012's plan fixes both: millisecond `at` + `%ID DESC`). Until that lands, two entries in the
  same second can swap between polls; a naive re-render would visibly reorder the list.
- **Decision**: `logview.ts` merges, not replaces: entries already shown keep their first-seen
  sequence; a poll only appends entries it has not seen (newest-first API order means new entries
  land at the chronological end). Ties flipping in the API order therefore cannot reorder what
  was displayed. Once 012's ordering fix lands, the same merge stays correct (it just never has
  to paper over ties).

## R-4 Copying on every origin the canvas is served from

- `navigator.clipboard` requires a secure context: `localhost:52773` qualifies, the public tunnel
  is https, but plain http on a LAN address does not.
- **Decision**: use the clipboard API with a transient "Copied" state, and keep entry and block
  text selectable as the always-available fallback (no `user-select: none` anywhere). e2e runs
  with granted clipboard permissions and asserts pasted text equals shown text (SC-002).

## R-5 Rendering a stored result faithfully

- A declared step's `result` is JSON text, at most 8000 characters; when larger, the stored JSON
  itself carries `"truncated": true, "omitted": <n>` (README, spec 005). The wire sends it as a
  parsed object (`{}` when none). The backend already degrades invalid JSON to `{}`.
- **Decision**: pretty-print the object in a scrollable `pre` (max-height, RunNode's
  failure-reason pattern); when `truncated === true`, show a "truncated by the product's size
  limit — N omitted" line with the reported count; copy copies the JSON text exactly as received.
  The UI never re-truncates and never hides the marker.

## R-6 Where the step detail lives

- Candidates: a modal dialog (hides the live run), a right-side drawer over the canvas (new layout
  surface), or the existing rail (the run view's detail column). The catalog set the precedent:
  an addressed side panel (`?view=catalog&task=4`) beside the list.
- **Decision**: the rail. `?run=<guid>&step=<id>` addresses it; a **STEP DETAIL** section renders
  above **RUN LOG**; the log narrows to the slice while a step is selected. Canvas nodes select
  via Svelte Flow's `onNodeClick` (independent of `elementsSelectable={false}`), so no drag or
  selection-mode behaviour changes. `RunMonitor` holds `selectedStepId` — the context both nodes
  and the rail already read.

## R-7 Surviving 500 live entries

- The panel re-renders every poll (1 s). Replacing the whole list each time drops the operator's
  scroll position and re-flows hundreds of rows.
- **Decision**: `mergeLog` returns the same entry objects when nothing changed (referential
  stability), keyed `{#each}` blocks, scroll preservation measured as distance-from-bottom (bottom
  distance is invariant to growth at the top of the list... entries only append at the
  chronological end, so preserve `scrollTop` on growth; restore "follow" only when the operator
  was already at the bottom). No virtualization until a real 500-entry run shows it is needed
  (YAGNI).
