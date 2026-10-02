# Evidence — 022 Runbook Gallery

Behaviour: [../spec.md](../spec.md) · Plan: [../plan.md](../plan.md) · Quickstart:
[../quickstart.md](../quickstart.md) · UI contract the tests enforce:
[../contracts/runbook-gallery.md](../contracts/runbook-gallery.md). No credential ever goes into
this directory; IRIS accounts and passwords come from the environment.

**Session constraint honoured**: nothing was committed (the user's "não commit nada") — all work
sits uncommitted in the worktree, on top of the finished `feat/spec021` session.

## Baselines (T002, captured 2026-10-01 before any 022 change)

| Check | Baseline |
|---|---|
| vitest | **32** files, **265** tests green (corrected: the 33/277 first recorded here was captured after T004 had already added `runbooks.test.ts`; 34/283 after Phase 3 = 32 + 12 + 6) |
| svelte-check | 0 errors, 0 warnings |
| IRIS suite (`zpm "test sentai-task -only"`) | green — **476** methods / 3374 assertions after T005's `TestWeeklyWindowMatchesFixture` (the 268 figure in AGENTS.md is stale; the suite grew with specs 013–021) |
| e2e spec files | **34** (spec 022 keeps 34: −`us20`, +`us31`) |
| last green full e2e | 2026-10-01 (spec 021's run) — **pre-existing shared-stack failure set** documented there: `us9-catalog-filters`, `us18`, `us23` (and docker-exec cases on this host's project naming) |

## Final state (T021, 2026-10-02)

| Check | Result |
|---|---|
| vitest | **35** files, **290** tests green (+12 runbook data, +6 useRunbook machine — the 6 retired `findExample`/`openExample` cases moved into it, +6 miniGraph, +7 runbookCards) |
| svelte-check | 0 errors, 0 warnings |
| IRIS suite | `Test SUCCESS` — **476** methods / **3374** assertions / 0 failed, including `DemoTest.TestWeeklyWindowMatchesFixture` (T005) |
| Full e2e | **34 files: 116 passed, 3 failed, 1 skipped** (15.6 min) — the 3 are spec 021's documented pre-existing set, unchanged by 022: `us18` perf and `us9` catalog perf (long-lived shared stack; us9 is the catalog screen the gallery never renders on) and `us23` (`docker compose stop ollama` — the service was removed from the compose files by commit d39fc99, spec 017) |
| `us31-runbook-gallery` | **17/17 passed** — all five stories' scenarios |
| `us21-getting-started` | **8/8 passed** — edited per plan D-9 (step 2 → *Browse runbooks*, first-use and theming scenarios → gallery); the guide's auto-open, keyboard and 1440 px fit unchanged |
| `us30-first-time-tour` | **9/9 passed** — the gallery-under-tour scenario replaces the invitation one; the z-index fix keeps the Tour button clickable over the gallery |

## Run log

| Date | Check | Result | Evidence |
|---|---|---|---|
| 2026-10-01 | Phase 2: `runbooks.test.ts` (12 cases: catalog, invariants, 3× fixture equality, slugs) | green | `npx vitest run src/lib/flows/runbooks.test.ts` — 12 passed |
| 2026-10-01 | Phase 2: IRIS two-sided sync — `DemoTest.TestWeeklyWindowMatchesFixture` | green | suite 476/476, 3374 assertions, `Test SUCCESS` (69 s) |
| 2026-10-01 | Phase 3 (US1): `miniGraph.test.ts` (6) + gallery e2e (4 scenarios) | green | `us31-gallery.json`, `us31-gallery-{dark,light}.png` |
| 2026-10-01 | Phase 4 (US2): `useRunbook` machine (6 unit cases) + Use e2e (5 scenarios) | green | `us31-use.json` (run completed via the example card) |
| 2026-10-01 | Phase 5 (US3): `runbookCards.test.ts` (7) + verdict/destructive e2e (2) | green | routed-empty-targets verdict, destructive marks |
| 2026-10-01 | Phase 6 (US4): coexistence e2e (5: precedence, tour, shared account, keyboard Use, theming) | green | `us31-cards-{dark,light}.png`; found and fixed: the dismissal now ends with the sign-out session (`signOut()` resets it) |
| 2026-10-01 | Phase 7 (US5): one ready-made path | green | guide + *Open flow…* → **Browse runbooks** → gallery; found and fixed: the shared entry closes the guide |
| 2026-10-02 | T021 full suites | green except the documented pre-existing set | the table above |
| 2026-10-02 | In-suite fixes the change required (suite honesty, plan D-9) | green | `us1` and `us22` start blank-canvas authoring from *Start from scratch* (FR-012) — the gallery is the empty canvas now |

## Guarantee mapping — us20 retired into us31 (plan D-9)

| Retired `us20` scenario | Where it lives now (`us31`) |
|---|---|
| offered on the empty canvas | *us31 gallery* — 7 cards, also with saved flows (FR-001) |
| opened, validated, run to the end | *us31 use* — the example card's Use: open, validate 0 errors, run COMPLETED |
| idempotent — never a duplicate | *us31 idempotent* — via *Open flow… → Browse runbooks → Use*: same id, rev 2 kept |
| guard over unsaved edits | *us31 guard* — over unsaved edits both entries (dialog + guide) ask; Cancel keeps the editor, Discard lands on the gallery |
| hidden when unavailable | *us31 verdict* — per card: disabled Use + `runbook-card-reason` naming the missing type/target (FR-007) |
