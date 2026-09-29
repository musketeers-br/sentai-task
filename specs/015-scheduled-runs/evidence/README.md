# Spec 015 evidence — Scheduled runs that execute

No password, token or secret value is recorded in any file here.

| File | What it shows |
|---|---|
| [t001-wallet-tasks.md](t001-wallet-tasks.md) | The spike (wallet, use-resource enforcement, `ApplyHTTP` sign-in, timing fields) and the findings of the acceptance runs |
| [acceptance-2026-09-29.txt](acceptance-2026-09-29.txt) | `scripts/schedule-evidence/acceptance.py` on the dev stack: **29/29** — the Task Manager fired the flow's task and the run completed (remote step on iris-target, in-process step as the run-as account); replace kept one task; without `SentaiSchedule:U` the firing recorded a failed run with the platform's `#822`; unschedule left no task and no secret; the password is in no product global |

## Regression (2026-09-29, branch `feat/spec015`)

| Suite | Result |
|---|---|
| Backend `%UnitTest` | 342/342 methods, 2309 assertions |
| Frontend unit (vitest) | 190/190 (+ `schedule.test.ts`) |
| e2e (Playwright, with iris-target) | 80 passed, 1 skipped, 2 failed, then us27 fixed and rerun 4/4. Remaining failure: `us19 duplicated tab`, known and unrelated (recorded since spec 011). us27's failure came from this spec: the Schedule dialog now has password fields, and us27 filled every "Password for" field on the page; it is now scoped to the *Run now* dialog |
| Acceptance (real firing) | 29/29 |

Found and fixed during the regression: a start time already past today was refused by the platform
(`ERROR #7432`) — the task now starts tomorrow in that case (e2e us28); the wallet collection
checked `SentaiSchedule:READ` instead of `USE` (acceptance) — the installer sets `:USE`/`:WRITE`.

Rewritten evidence of earlier specs was restored, except the four files whose content this spec
changes: `002 q5-schedule.json` (one task per flow; the password redacted), `007 us2-origin.json`,
`007 us4-suspend.json` and `007 sc003-timing.txt`.

Clean-up (T025): after the runs, the dev instance has no `SentaiTask:` task, no `SentaiTask.` wallet
secret, no `sched-test` account, no `us28-` flow and no schedule row.
