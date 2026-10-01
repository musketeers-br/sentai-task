# Implementation Plan: Flow Execution Log Detail

**Branch**: `feat/spec016` (feature dir `016-run-log-details`) | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (3 stories, 14 FRs, 6 SCs). User planning constraint: **MVP first —
there may not be time to implement everything by the deadline.** The plan is sliced so the first
increment ships alone and the last one is cut without loss. Pure frontend: the run read already
serializes every fact the spec needs ([R-1](research.md)); spec 012 (in parallel development)
provides the entries, and nothing here rebuilds its territory ([R-2](research.md)).

## Summary

1. **Step execution detail (US2 — the MVP).** Selecting a step — canvas node or step-list row —
   opens that step's execution account in the run view's rail, addressable as
   `?run=<guid>&step=<id>`: state, queued/started/finished times, duration, where it ran, as
   whom, the failure reason whole and copyable, and the result it produced, readable and
   copyable, with its truncation markers as stored. Works today with zero dependency on spec 012,
   because every field comes from the run read's steps, not from log entries — and the result is
   invisible in the canvas until this lands.
2. **Log reading experience (US2 slice + US1).** A pure `logview.ts` (named to avoid 012's
   planned `log.ts`) orders the panel chronologically, stabilizes entry order across polls
   ([R-3](research.md)), labels severities INFO/WARN/ERROR beyond colour, narrows to the
   selected step's slice across all its attempts, keeps the operator's scroll position with a
   one-action jump to the newest, and gives every entry a copy affordance. Long messages wrap,
   never truncate; empty logs stay honest.
3. **Filters (US3 — cut first if the deadline hits).** Severity narrowing composable with the
   step slice, "N of M" counts, one-action clear.

## MVP and the deadline

| Slice | Contents | Ships alone? | If the deadline arrives here |
|---|---|---|---|
| **MVP** — Increment 1 | Step execution detail incl. result (US2 core) | Yes — no dependency on 012 or on any other increment | The feature already delivers "detalhes da execução" per step: reason, result, times, place, identity |
| Increment 2 | Step log slice + panel guarantees (rest of US2 + US1) | Yes, after 1 | The log is readable, whole, copyable; entries appear as soon as 012's recording lands |
| Increment 3 | Severity filter + counts (US3, P2) | Yes, after 2 | **Cut.** US3 is P2 by design; nothing else depends on it |

The increments are ordered so stopping after any one of them leaves the product better and
nothing half-built. Increment 1 is also the smallest, so it lands fastest.

## Impact note — after the 2026-09-29 pull (specs 012, 013, 015 Merged)

The pull merged the parallel features this plan steered around. Verified impact, decision by
decision:

- **The backend now writes log entries** (012's narrator, `ORDER BY at DESC, %ID DESC`, ms
  timestamps) — the blocked-by-012 guards in later phases can see real content, and R-3's
  tie-flip risk is fixed server-side.
- **012's panel baseline landed**: `log.ts` (`chronological`, `severityLabel`,
  `EMPTY_LOG_TEXT`), chronological panel, severity text + colour, follow-scroll, wrap-anywhere.
  Increment 2 therefore shrinks to: copy per entry, *Jump to latest*, the slice, and 013-style
  reuse — nothing is rebuilt.
- **013 landed result display**: `run.ts` maps `result` (`resultOf`, `{}` → null — **D-5's wire
  part is done**), `result.ts` + `ResultPanel.svelte` + `JsonTree.svelte` render it, with report
  findings and the stored truncation markers. 016's detail **reuses** `ResultPanel` instead of
  building a parallel result block (D-4 updated); 013's `us27-area-steps.spec.ts` pins the
  node-Result-button → `result-panel` → Close contract, which stays untouched.
- **013's selection is in-memory only** (`RunMonitor.resultFor`, only for finished steps with a
  result) — 016's addressed selection `?run=&step=` (any step, full account, node/row click)
  remains this feature's core delta. Selection follows the house address precedent
  (`selectTask`/`selectTarget`): plain `goto`, so **back closes the selection** (data-model §5's
  `replaceState` idea is dropped for the house pattern).
- **e2e numbers moved**: `us27` (013) and `us28` (015) are taken — 016 takes **us29, us30,
  us31**.
- **`logview.ts` → extend 012's `log.ts`**: the file-collision risk is gone; one module owns the
  log's display shape (SoC). D-6 updated.
- **D-5's openapi doc delta remains**: `StepRun` still does not document `result`,
  `executedOn`, `executedAs` (verified post-pull).
- **The running container predates the pull**: `zpm "load /home/irisowner/dev"` re-run before
  grounding and e2e (done, 2026-09-29).

## Technical Context

**Language/Version**: TypeScript 5.9 + Svelte 5 (runes) + SvelteKit (static build), Svelte Flow
for the run canvas. **No backend change** ([R-1](research.md)).

**Primary Dependencies**: none new (no new npm packages; the copy affordance uses the platform
clipboard API).

**Storage**: none persisted — screen state only. The selected step travels in the address
(`?run=<guid>&step=<id>`), like the catalog's `?view=catalog&task=4`.

**Testing**:
- vitest (pure modules): `stepdetail.test.ts` (detail view model, result/truncation handling,
  copy texts), `logview.test.ts` (chronological order, stable merge across polls, slice, labels,
  unknown severities, counts).
- `npm run check` (svelte-check) must stay clean.
- Playwright: `us27-step-detail.spec.ts`, `us28-log-panel.spec.ts`, `us29-log-filters.spec.ts` —
  numbered after 012's planned `us24`–`us26` ([R-2](research.md)). `us27` needs no log entries;
  `us28`'s entry-content assertions are tagged **blocked-by-012** and pass once 012's recording
  increment lands; its affordance assertions (labels, copy, jump, wrap, honest empty) run with
  whatever entries exist.

**Target Platform**: the canvas as IRIS serves it at `/csp/sentai/`; e2e drives the container's
baked bundle (`bash scripts/publish-canvas.sh` first) or the Vite redirect.

**Project Type**: web application (frontend slice of an existing one).

**Performance Goals**: SC-003 — 500 entries in the panel during a live run: keyed rendering with
merge-not-replace per poll ([R-7](research.md)), scroll position preserved; the rest of the run
view keeps its 1 s poll cadence.

**Constraints**: platform text verbatim and whole (Constitution III); severity distinguishable
without colour alone, in both themes; UI text in English; components never call `fetch`; no new
screen — everything lives in the existing run view; must merge cleanly with 012's panel work.

**Scale/Scope**: 2 new pure modules (+tests), 1 new component, ~5 touched files, 3 e2e specs,
1 additive openapi documentation delta.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | New code is components (`StepDetail.svelte`, `RunScreen`) over pure view models (`stepdetail.ts`, `logview.ts`) over the existing wire (`run.ts` ← `api/client.ts`). No new HTTP, no fetch in components; selection state lives in the existing run context, the address carries it. | ✅ |
| **II Closed Capability Set** | No new operation, no input-driven code; the detail renders declared data the run read already returns. Query parameter `step` is a value (a step id), never a name of code. | ✅ |
| **III Delegated Authorization** | Read-only view over data the operator already fetched with their own credential; failure reasons and results are shown and copied exactly as stored, never paraphrased or re-truncated. | ✅ |
| **IV Errors as Values** | No new failure paths: the run view's existing `ApiResult` and tagged states carry transport problems; an empty log, a truncated result and a not-yet-started step are values with honest text, never exceptions or errors. | ✅ |
| **V Verifiable Increments** | Three increments, each user-observable end-to-end with its failing e2e written first; the dependency on 012's recording is declared and confined to entry-content assertions (us28 tag); the MVP has none. | ✅ |
| **VI Technology Agnosticism** | The spec stays technology-free; choices live here and in research. | ✅ |
| SOLID / SoC | Ordering, merging, slicing and counting live only in `logview.ts`; detail shaping only in `stepdetail.ts`; the components only render. | ✅ |
| TDD | Failing unit + e2e tests first in every increment (tasks phase enforces order). | ✅ |
| YAGNI | US3 kept as the last, cuttable slice; no log-text search, no export (012 owns it), no virtualization until 500 entries prove it needed. | ✅ |
| Reproducibility | Unchanged commands; quickstart lists them. | ✅ |

## Project Structure

### Documentation (this feature)

```text
specs/016-run-log-details/
├── plan.md              # this file
├── research.md          # R-1…R-7
├── data-model.md        # view models over the existing run read
├── quickstart.md        # how to see it working
├── contracts/run-view-delta.md   # address + consumed fields + panel display contract
├── checklists/requirements.md
└── evidence/            # README table, added as increments land
```

### Source Code (repository root)

```text
frontend/src/lib/run/stepdetail.ts          # new: detail view model + copy texts (+ .test.ts)
frontend/src/lib/run/logview.ts             # new: order, stable merge, slice, labels, counts (+ .test.ts)
frontend/src/lib/run/StepDetail.svelte      # new: the rail's STEP DETAIL section
frontend/src/lib/run/RunScreen.svelte       # rail: detail section + panel upgrade + selection
frontend/src/lib/run/RunNode.svelte         # selected styling (state comes from the run context)
frontend/src/lib/run/monitor.svelte.ts      # selectedStepId (view state, context-shared)
frontend/src/lib/run/run.ts                # StepRunView.result; fromWireRun maps it
frontend/src/routes/+page.svelte            # ?step= read/write beside ?run=
frontend/tests/us27-step-detail.spec.ts     # new (no 012 dependency)
frontend/tests/us28-log-panel.spec.ts       # new (entry-content assertions blocked-by-012)
frontend/tests/us29-log-filters.spec.ts     # new (P2 — cut first)
specs/002-canvas-ui/contracts/openapi.yaml  # StepRun: document result/executedOn/executedAs (doc-only)
README.md                                   # Logs row: the run view now shows each step's result
```

**Structure Decision**: the frontend-only layout above; no `src/` (backend) files change — the
only repository-root artifact outside `frontend/` is the openapi documentation delta.

## Decisions

- **D-1 No backend work.** `ShapeStepRun` already serializes `result` (parsed stored JSON, `{}`
  when absent or invalid), `executedAs` and `executedOn` (`local` default). The only backend-adjacent
  change is documenting those three fields in the openapi `StepRun` schema — additive, doc-only
  ([contracts/run-view-delta.md](contracts/run-view-delta.md)).
- **D-2 Selection is addressable.** `?run=<guid>&step=<id>`, handled exactly like the catalog's
  `task` parameter: `+page.svelte` reads it beside `run` and passes it to `RunScreen`; selecting
  or deselecting rewrites the address with the existing `syncUrl` pattern, so reload, back and
  forward work. Click targets: canvas nodes via Svelte Flow's `onNodeClick` (works with
  `elementsSelectable={false}`) and step-list rows. `RunMonitor` gains `selectedStepId` so nodes,
  rows, panel and detail share one source of truth.
- **D-3 The detail lives in the rail.** When a step is selected, a **STEP DETAIL** section
  renders above **RUN LOG** in the existing rail (the catalog's detail panel is the precedent for
  an addressed side panel). Layout stays one column; the result renders in a scrollable `pre`
  (RunNode's failure-reason pattern) with a max-height, so a large report never pushes the rail.
  While a step is selected, the log narrows to its slice (FR-010); the section's close affordance
  deselects and restores the full log.
- **D-4 Result rendering is faithful.** The stored object is pretty-printed; when it carries
  `truncated: true` (the product's size limit already embeds the marker with `omitted`), the
  detail shows a line saying so with the omitted count, exactly as reported. Copy copies the
  JSON text exactly as received — no re-formatting, no re-truncation.
- **D-5 Wire mapping.** `StepRunView` gains `result: Record<string, unknown> | null` (`{}` →
  `null`); `fromWireRun` maps it. Everything else the detail shows is already mapped
  (`state`, times, `failureReason`, `executedOn`, `executedAs`).
- **D-6 `logview.ts` owns the log's shape.** `chronological(log)` reverses the API's newest-first
  order; `mergeLog(prev, next)` re-keys by first-seen sequence so a poll never reorders what was
  already shown (tie flips in `at` are invisible; [R-3](research.md)); `sliceFor(log, stepId)`
  keeps only that step's entries, across all attempts, while the detail itself shows the latest
  attempt (already `fromWireRun`'s rule); `severityLabel(severity)` yields `INFO` / `WARN` /
  `ERROR` and passes an unknown severity through as its own uppercased word, never dropped.
- **D-7 Copy affordance.** One *Copy* button per entry and per detail block (reason, result);
  `navigator.clipboard.writeText` with a transient "Copied" state. Text stays selectable as the
  fallback for origins where the clipboard API is unavailable ([R-4](research.md)); e2e grants
  clipboard permissions and asserts the pasted text equals the shown text.
- **D-8 Follow behaviour.** While live, the panel keeps the newest entry visible; if the
  operator has scrolled up (bottom distance above a small threshold), polls preserve the scroll
  position and a *Jump to latest* affordance appears — one action returns to the newest. A
  terminal run opens at the newest.
- **D-9 Boundary with spec 012.** 012 owns what is recorded, the *Runs* history screen, export,
  and its own panel baseline (chronological panel, text labels, empty-log wording). 016 builds
  the reading experience to the spec's contract, not to 012's code: its tests are written
  against [contracts/run-view-delta.md](contracts/run-view-delta.md); if 012's panel lands first,
  016 skips what is already there, and its `logview.ts` (not `log.ts`) and `us27+` test names
  avoid 012's files. The shared surface is `RunScreen.svelte`'s log section — the one known
  coordination point.
- **D-10 Empty and not-yet-started honesty.** A run with no entries keeps an honest empty text —
  012's wording once it lands ("No log was recorded for runs before this version." for legacy
  runs); until then today's text stays for genuinely empty logs. A selected step that has not
  started shows its state and `—` for unknown times, duration, place and identity (FR-011) —
  never placeholders that read like values.
- **D-11 Wrap, never truncate.** Log entries and detail blocks use `white-space: pre-wrap` +
  `overflow-wrap: anywhere`, so a long reason, a long token, or JSON with no spaces wraps inside
  the panel without breaking layout; SC-002's test compares the entry's full text against what
  the DOM carries.

## Increments

| # | Story | First failing test | Then |
|---|---|---|---|
| 1 | US2 core — step execution detail (**MVP**) | `stepdetail.test.ts`; `us27-step-detail.spec.ts` (dispatch a flow with `db-size-report` + a failing `storage-headroom-check`; open each step's detail: result readable, reason whole, copy works, `?run=&step=` round-trips) | wire mapping, `stepdetail.ts`, `StepDetail.svelte`, selection + address |
| 2 | US2 slice + US1 — log reading experience | `logview.test.ts`; `us28-log-panel.spec.ts` (affordances now; entry-content tagged blocked-by-012) | `logview.ts`, panel upgrade: labels, copy, jump-to-latest, scroll preservation, wrap, slice on selection |
| 3 | US3 — filters (P2, cut first) | `logview.test.ts` counts/filter; `us29-log-filters.spec.ts` | severity narrowing + "N of M" + one-action clear |

## Complexity Tracking

No violations.

## Constitution re-check after Phase 1

Still passing. The design touches presentation and view models only: no new operation exists, no
permission is inferred or cached, platform text stays verbatim and whole end-to-end (shown,
wrapped, copied exactly), empty and truncated states remain values, and every increment is
independently observable with its failing test first. The one cross-spec dependency (012's log
recording) is declared, confined to tagged e2e assertions, and absent from the MVP.
