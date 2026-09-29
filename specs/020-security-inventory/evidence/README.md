# Spec 020 evidence — Security inventory

No secret value, key material, client secret or password is recorded in any file here (T028 scan:
no match for `PRIVATE KEY`, `PrivateKeyPassword`, `ClientSecret`).

| File | What it shows |
|---|---|
| [t001-security-reads.md](t001-security-reads.md) | The spike: every route on the primary and on iris-target, OAuth client-side fields (with a temporary server definition and client), the demo account's 403, the reader's error id, and the privileges per route found by the acceptance run |
| [acceptance-2026-09-29.txt](acceptance-2026-09-29.txt) | `scripts/security-evidence/acceptance.py`: **11/11** — a certificate expiring in 10 days made the **scheduled** run (spec 015, fired by the Task Manager) fail, naming the certificate, run as the run-as account; OAuth "not configured" completed; no key material in the stored results |

## Baseline and regression (2026-09-29, branch `feat/spec020`)

| Suite | Baseline (feat/spec015) | After |
|---|---|---|
| Backend `%UnitTest` | 342 methods | **365/365** (2508 assertions) |
| Frontend unit (vitest) | 190 | 190/190 (no frontend source change: palette, inspector and result panel already serve the three types, T025) |
| e2e (Playwright, with iris-target) | 82 + 1 skipped | **84 passed**, 1 skipped, 1 failed: `us19 duplicated tab`, known and unrelated (recorded since spec 011) |
| Acceptance (real scheduled firing) | — | 11/11 |

## Found and fixed during implementation

- `ReadExecutor.FitResult` added its `truncated`/`omitted` markers after trimming, so they could push
  a report back over the limit and cost a finding; the markers are now counted while trimming.
- A full permissions inventory does not fit the stored result (details are cut): totals are now kept
  in `summary` (`roles`, `resources`, `credentials`, `configurations`), which is never cut.
- OAuth reads need the three OAuth 2.0 administration resources besides `%Admin_Secure`
  (t001 §5); documented in the README.

Clean-up (T030): no `sentai-e2e-020-*` credential, no OAuth server definition, no `SentaiTask:`
task, no `sched-test`/`probe020` account and no `us29-` flow is left on the dev instance.

## After merging `master` (specs 011–015 merged, 017 semantic search added)

Conflicts resolved in the step-type catalog (017 gave every entry a `description`; the three new
entries got one), `docs/limitations.md` (both sections kept) and `.specify/feature.json`. Then:
backend **418/418** (2938 assertions), vitest **216/216**, svelte-check 0 errors, e2e us29 + us27
**8/8** against a republished canvas.
