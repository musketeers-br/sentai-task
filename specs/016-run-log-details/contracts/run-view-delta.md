# Run view delta: Flow Execution Log Detail

Additive, frontend-only. The API does not change; one openapi schema gains documentation for
fields it already serves. Numbering follows the spec's FRs.

## 1. `GET /runs/{guid}` — fields consumed as-is

`StepRun` (served today by `ShapeStepRun`; documented additively in
`specs/002-canvas-ui/contracts/openapi.yaml`):

```yaml
StepRun:
  # … existing properties unchanged …
  executedAs:
    type: string
    description: Who ran the step (spec 005); empty for steps the platform runs.
  executedOn:
    type: string
    description: Where the step ran — "local" or a target server's name (spec 008).
  result:
    type: object
    additionalProperties: true
    description: >
      The step's stored report (spec 005), {} when none. When the product's size limit
      (8000 characters) cut the stored report, the object itself carries
      "truncated": true and "omitted": <n>; the view shows those markers as data.
```

`log` is consumed exactly as served: newest-first `{at, stepId, severity, message}`. The panel
reverses it for display; nothing is paraphrased, re-ordered beyond §3's stabilization, or
truncated.

## 2. Address contract

| Pattern | Meaning |
|---|---|
| `?run=<guid>` | the run view, no step selected (today's behaviour) |
| `?run=<guid>&step=<stepId>` | the run view with that step selected: **STEP DETAIL** in the rail, log narrowed to its slice |

- `step` naming a step absent from the run's flow ⇒ selection ignored (unselected view).
- Selection/deselection uses `replaceState` (the catalog's `?task=` precedent) — back/forward
  work, no history spam.
- No new `view` value; the run view keeps its current wiring.

## 3. Log panel display contract (run view rail)

| Aspect | Contract |
|---|---|
| Order | chronological (oldest first); entries already shown keep their order across polls (first-seen stabilization; backend tie-fix belongs to 012) |
| Entry | time · `#step` (when it concerns one) · severity label · message |
| Severity | `INFO` / `WARN` / `ERROR` text label + colour; distinguishable without colour in both themes; unknown severity passes through, never dropped |
| Message | whole: wraps (`pre-wrap`, `overflow-wrap: anywhere`), never truncated; one *Copy* per entry copies exactly what is shown (SC-002) |
| Live | new entries appear within the view's normal refresh; newest stays visible unless the operator scrolled up; scroll position survives polls; one *Jump to latest* action returns to the newest |
| Step slice | a selected step narrows the panel to that step's entries (all attempts); deselect restores the full log |
| Empty | honest text, never an error — 012's wording for pre-recording runs once it lands; today's text for genuinely empty logs |
| Filters (US3) | severity narrowing composable with the slice; "N of M entries" count; one action clears; a match of nothing says so honestly |
