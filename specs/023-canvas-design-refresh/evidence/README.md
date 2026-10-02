# Evidence — spec 023 Canvas Design Refresh

No credentials in any file here. Screenshots are 1440 × 900 unless the name says otherwise; each
row names the Claude Design board (section 05) it follows.

## Baseline (T002, 2026-10-01, branch `023-canvas-design-refresh` at `42d0efb`, before any spec 023 code)

| Check | Result |
|---|---|
| Backend `zpm "test sentai-task -only"` (after `LoadDir` of `src` and `tests`) | `All PASSED` — 475 methods, 3370 assertions |
| `npm run check` (svelte-check) | 0 errors, 0 warnings (569 files) |
| `npm test` (vitest) | 29 files, 246 tests passed |
| `npx playwright test` (full suite, bundle published from `master`'s code) | 98 tests: **92 passed, 5 failed, 1 skipped** (18.4 min) |

The five failures exist on `master` before this spec; none touches what spec 023 changes:

| Spec | Failure | Cause as observed |
|---|---|---|
| us19 duplicated tab (FR-013) | `keyboard.press: Target page, context or browser has been closed` | the second tab closed under the test |
| us22 SUGGESTED group | SUGGESTED group not visible | semantic search answered with no suggestion on the dev stack |
| us22 corpus | corpus size `> 0` expected, got 0 | the ranking corpus was empty on the dev stack (spec 017 worker) |
| us23 provider down | `docker compose -f docker-compose.yml stop ollama` failed | the `ollama` service was removed by spec 017; the test still stops it |
| us29 step detail | object equality, 87 lines differ | the step-detail payload differs from the test's expectation |

Evidence files the baseline run rewrote under other specs (`specs/0xx/evidence/`) were restored with
`git checkout`.

## US1 runs (T020, 2026-10-01)

| Check | Result |
|---|---|
| `npm run check` / `npm test` | 0 errors / 31 files, 265 tests passed |
| `npx playwright test tests/us30-flow-chrome.spec.ts` | 7 passed |
| Full suite on the US1 bundle | 105 tests: 92 passed, 12 failed, 1 skipped — the 5 baseline failures plus 7 new |
| The 7 new, after fixes, rerun with us30 (`us6`, `us13`, `us16`, `us17`, `us21`, `us22-cancel-alert-notice`, `us30`) | **31 passed** |

The 7 new failures and what was done:

| Spec | Cause | Fix |
|---|---|---|
| us6, us13, us21 theming | palette category counts used `--color-text-faint` (3.53:1 in light) | counts use `--color-text-muted` |
| us17 New flow | expected the old meta text "not saved yet" | the flow bar says "unsaved" (board); test updated |
| us21 top bar | `getByRole('button', { name: 'Task catalog' })` also matched "Import from the task catalog" | scoped to the top bar, `exact: true` |
| us16 run, us22 cancel | timing (a wave still running; a response read after disposal) | none — both passed on rerun |

## US2 runs (T033, 2026-10-02)

| Check | Result |
|---|---|
| Backend `zpm "test sentai-task -only"` | `All PASSED` — 482 methods (475 + 7 for `counts`, `unclassifiedOnly`, `description`) |
| `npm run check` / `npm test` | 0 errors / 283 tests passed |
| `us31-catalog-attention` + `us10-catalog-suspend` | 8 passed |
| Full suite on the US2 bundle | 111 tests: **104 passed, 6 failed, 1 skipped** — the 5 baseline failures plus `us22-cancel-alert-notice:65`, which passed 2/2 on an isolated rerun (timing, as in the US1 run) |

## Spec 023 runs

| File | Proves | Board | FR / SC |
|---|---|---|---|
| `us30-empty-canvas-dark.png` / `us30-empty-canvas-light.png` | global bar, flow bar with "unsaved" and the visible reason "add a step to enable running", empty-canvas card, inspector FLOW / "Nothing selected", palette counts and "Show N more" | *Proposed — flow chrome* | FR-001, FR-005–FR-010, FR-013 |
| `us30-flow-chrome-dark.png` | three steps and one join dragged through the card; status bar "3 steps · 1 join · 0 destructive" | *Proposed — flow chrome* | FR-007, FR-011 |
| `us30-palette-dark.png` | search finds a type from a collapsed group | *Proposed — flow chrome* | FR-013 |
| `us30-flow-chrome-1280.png` | every flow action in view at 1280 × 800, no horizontal scroll | *Proposed — flow chrome* | SC-001, spec assumption (1280 px) |
| `a11y-us30-flows-dark.json` / `a11y-us30-flows-light.json` | axe on Flows: 0 serious/critical; 3 moderate page-level findings (`landmark-one-main`, `page-has-heading-one`, `region`) that predate this spec | — | SC-008 |
| `us31-catalog-counts.png` | header "M of N tasks · updated N s ago", Suspended / Destructive counts, "N unclassified", footer with the API's totals | *Proposed — Task catalog* | FR-015, FR-016 |
| `us31-counts.json` | the counts the screen showed, as the API returned them (also with `unclassifiedOnly=1`) | — | SC-005 |
| `us31-detail-destructive.png` | Purge Tasks: DESTRUCTIVE, "Why this is destructive" from the step-type catalog, "created outside SentaiTask", the platform's description, Add to a flow, the Suspended switch | *Proposed — Task catalog* | FR-017, FR-018, FR-020, FR-020a |
| `us31-suspend-confirm.png` | the simple confirmation for a SentaiTask flow task, naming the flow whose scheduled runs stop | *Proposed — Task catalog* | FR-020 |
| `us31-catalog-light.png`, `a11y-us31-catalog-{dark,light}.json` | catalog with a detail open: 0 serious/critical; 1 moderate page-level finding (`landmark-one-main`) that predates this spec | — | SC-008 |
