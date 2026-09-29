# Evidence — 011 Semantic Step-Type Search

Rule: no token, password or refresh token ever goes into an evidence file. JSON records hold
queries, types, scores and reasons only.

## Files this feature produces

| File | Task | What it shows |
|---|---|---|
| `us22-suggested-intent.png`, `us22-semantic-search.json` | T031 | The SUGGESTED group for an intent sentence, the entry offered once, the drag-add (FR-001, FR-003, FR-021) |
| `us23-degraded.png`, `us23-search-degradation.json` | T032 | With `ollama` stopped: today's palette, today's no-match message, no SUGGESTED group, no error (FR-023) |
| `api-story1-3.txt` | T033 | Quickstart steps 5/6/13/17: intent ranking descending, the empty floor answer, no invented entry, every catalog description non-empty |
| `api-story2-degradation.txt` | T033 | Quickstart steps 9–11: HTTP **200** `unreachable` with the provider stopped; `not-configured` with the row deleted |
| `api-story4-add.txt` | T033 | Quickstart steps 19–20: a new catalog entry found by its description (rank 1, 0.83), corpus rebuilt to the catalog (10 rows, one version), idempotent re-search |
| `api-story4-remove.txt` | T033 | Quickstart step 21: the removed entry's corpus row deleted (9 rows) and the entry no longer offered |
| `build-bootstrap.txt` | post-feature | Fresh-boot verification: provider row baked by the build, corpus self-built on first search, e2e and suite green on a rebuilt image — and the zpm-stdin trap that forced the second session |
| `gates.txt` | T034 | The final gates: `zpm "test sentai-task -only"` green with **no** `%Embedding.Config` row (CI state), `SELECT COUNT(*) = 0`; `npm run check` clean, vitest green, Playwright green |

## Walkthrough notes (quickstart.md, run 2026-09-28)

- **Story 1** — `rotate the journal`, `get rid of old audit records`, `free up disk space` on the
  canvas: covered by `us22-suggested-intent.png` (same bundle, same queries); the API side is
  `api-story1-3.txt`. Warm palette latency is under a second end to end (the e2e test's 30 s
  budget includes the corpus build; steady state is far under SC-003's 1 s).
- **Story 2** — steps 8/9/11 in `api-story2-degradation.txt` and `us23-degraded.png`. The `slow`
  and `incompatible` rows of step 10's table are the suite's own cases
  (`StepSearchServiceTest.TestSlowProviderIsUnavailableSlow`,
  `TestIncompatibleProviderIsUnavailableIncompatible`) — reproducing them here would mean breaking
  the dev stack's provider for minutes at a time; the suite proves the same answers hermetically.
- **Story 3** — step 13/15/17 in `api-story1-3.txt`; step 14's drop-unknown-identifier behaviour is
  the palette view model's contract case 7 (`search.test.ts`); step 16's un-addable legacy entry is
  contract case 8 and `us22`'s rendered palette. The class-name queries
  (`TestClassNamesAreNotSearchKeys`) and the description-derived corpus row
  (`TestCorpusRowIsDerivedFromTheDescription`) are the suite's structural proofs.
- **Story 4** — `api-story4-add.txt` / `api-story4-remove.txt`: the entry alone is enough — the
  corpus noticed the catalog change in both directions with no manual step, and the rebuild is
  idempotent (one `corpusVersion` across rows; identical scores on the re-search). The empty
  description rejection (FR-015) is `StepTypeTest.TestEveryEntryHasADescription`.
- **Regression gate (step 22)** — the local filter's behaviour on `integrity`, `purge`, `journal`,
  `compact`, `custom` and the empty box is held verbatim by `filterLocally`
  (`search.test.ts`, "keeps today's substring rule") and by `us23`'s local-filter assertions with
  the provider down; SUGGESTED is purely additive.
- The temporary `backup-due-report` catalog entry used for Story 4 was removed again and the
  catalog reloaded before the final gates; `git status` shows the catalog file unmodified.
