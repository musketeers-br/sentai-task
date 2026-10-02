# Evidence — 021 First-Time Canvas Tour

No credentials in this file, ever. Automated evidence lands here via
`frontend/tests/us30-first-time-tour.spec.ts` (`envelope` JSON + screenshots); the manual runs
record their outcomes in the table at the end.

## Baseline (T002, recorded 2026-10-01 before any 021 change)

| Suite | Before 021 |
|---|---|
| vitest (`cd frontend && npm test`) | 246 tests, 29 files, all passing |
| `npm run check` (svelte-check) | 0 errors, 0 warnings |
| e2e (`npx playwright test`, baked bundle) | 33 spec files, 98 tests: **76 passed, 21 failed, 1 skipped** (13.7 min) |

## Final (T017, 2026-10-01, with `SENTAI_CONTAINER=sentai-task1-iris-1`)

| Suite | After 021 |
|---|---|
| vitest | **265 tests, 32 files, all passing** (+19 for `lib/tour`) |
| `npm run check` | 0 errors, 0 warnings |
| e2e | 42 spec files, 107 tests: **85 passed, 21 failed, 1 skipped** (16.6 min) |
| `us30-first-time-tour` | **9/9 passed** — SC-001, SC-003 and every US1–US3 case |
| `us21-getting-started` (spec 010 guard, unedited) | **7/7 passed** — the guide's auto-open, keyboard case and 1440 px fit are unchanged |

### The 21 failures: all pre-existing, none from 021

This host runs the compose stack under the project name `sentai-task1` (container
`sentai-task1-iris-1`), so every test that shells into the default `sentai-task-iris-1` fails
here regardless of code (`frontend/tests/iris.ts` honors `SENTAI_CONTAINER`; runs on this host
must set it). With the override set, the remaining failures are shared-stack state: the
baseline already failed `us7-catalog navigation` (docker exec; with the override, the platform
list no longer contains the "Integrity Check" task the test asserts), `us9-catalog-filters`
(150-task seeding vs the residue on this long-lived dev instance), `us29-overview` F, `us20`,
`us28`, `us29-security-inventory`, `us10`, `us8`, `us18`, `us23` — the identical failure set as
the pre-change baseline, modulo known flakiness (`us13-management-theming` failed in the full
run and passed in isolation minutes later). **No failure exists that the 021 diff can reach:**
the failing assertions are platform task lists, schedules and fixtures; the 021 change touches
only the Flows screen, the shared focus helper (proven behaviour-identical by us21's keyboard
case) and two inert `data-tour-target` attributes.

## Evidence table

| Check | Artifact | Status |
|---|---|---|
| SC-001 — three marks, anchored, dark and light | `us30-tour-mark{1,2,3}-dark.png`, `us30-tour-mark1-light.png`, `us30-tour.json` | ✅ `us30` 9/9 |
| SC-002 — *Getting started* dialog unchanged (us21 green, unedited; no new failures) | suite comparison above | ✅ |
| SC-003 — keyboard-only traverse/finish; Escape skips | `us30` keyboard case (Tab ×15 inside, Escape, focus return) | ✅ |
| SC-004 — 3 of 3 first-time operators complete the loop (manual) | table row below | [external] T018, due 2026-10-04 |

## SC-004 usability spot-check (T018, [external])

| Operator | Date | Completed add → connect → validate → run unaided | Notes |
|---|---|---|---|
| — | — | — | pending — owned by the team, before voting ends 2026-10-04 |
