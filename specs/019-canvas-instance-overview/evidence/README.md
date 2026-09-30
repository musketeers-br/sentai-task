# Evidence — spec 019 Canvas Instance Overview

Dev stack, 2026-09-29: `sentai-task-iris-1` (image `sentai-task-iris-018`, IRIS 2026.2) mounting this
worktree read-only, spec 018 loaded (`zpm load`), canvas published with `scripts/publish-canvas.sh`;
`iris-target` running. No credential in any file here: temporary operators use random passwords that
are never written down and are deleted by the test that creates them.

## Baseline and regression

| Check | Before (T001) | After (T030) |
|---|---|---|
| `npm test` (vitest) | 216 tests, 26 files | **236 tests**, 28 files — `overview.test.ts` (15), `screen.test.ts` (5) |
| `npm run check` | 0 errors, 0 warnings | 0 errors, 0 warnings |
| Backend suite | 440 methods (spec 018) | 440 / 440, `All PASSED` |
| Playwright `us29-overview` | — | 7 / 7 |
| Full Playwright | — | 91 run: 84 passed, 1 skipped; then the 6 specs touched below re-run green (30 / 30) |

### Full-run failures and what they were

| Spec | Cause | Outcome |
|---|---|---|
| us17, us21, us25 (top bar fits at 1440 px) | The fifth tab (*Overview*) pushed *Sign out* past the edge — this feature | Fixed in `TopBar.svelte` (tab padding 5 px, gaps 2/5 px, flow-name field may shrink to 72 px); all green on re-run |
| us15, us16 (targets, remote run) | The `sentai-task-iris-target-1` container and the `sentai-task-iris` / `sentai-task-iris-target` images had disappeared from the host during the session (not removed by this work); `ERROR #6059` reaching `iris-target:52773` | `iris-target` recreated from the compose file; both green on re-run |
| us23 (search degradation) | Stops and starts the `ollama` compose service, which spec 017 removed from `docker-compose.yml` on `master` | Pre-existing on `master` since spec 017; not touched here |

## us29 cases

| Case | Covers | Result |
|---|---|---|
| A | US1, SC-001, SC-002 — sign-in with no query lands on *Overview*; 11 cards `ok`; headline text equal to the `GET /overview` answer the page received; no "CPU" label | pass — [us29-overview-ok.png](us29-overview-ok.png) |
| B | SC-003 — temporary account with the public demo's primary resources (`scripts/demo/lib.sh`, role `SentaiE2EDemo`) | pass: `security`, `web-apps`, `secrets` refused with `HTTP 403 — HTTP 403: no reason given` (the platform sent an empty status), 8 cards `ok` — [us29-overview-refused.png](us29-overview-refused.png) |
| C | US2 — *Processes*: sort by *Commands* desc, filter `IRISAPP`, compared with the reading the page received; the address reopens the view in a new page | pass — [us29-processes.png](us29-processes.png) |
| D | SC-006 — auto-refresh on with the tab hidden for 25 s | 0 reading requests; a read within 5 s of becoming visible |
| E | US3, SC-005 — *Web applications* report on demand vs a one-step run opened in the run view | same findings, same order and text; card keeps counts and *Open report* across *Refresh* — [us29-report-card.png](us29-report-card.png) |
| F | US4, SC-004 — *Secrets* → *Schedule this check* → *At* + password + *Schedule* (4 actions) | scheduled daily a minute ahead; the scheduled run completed with the secrets inventory; unscheduled and flow deleted — [us29-schedule-dialog.png](us29-schedule-dialog.png) |
| H | SC-007, SC-008 — `?view=catalog|targets|runs|flows` open what they name; both themes | pass — [us29-overview-light.png](us29-overview-light.png), [us29-overview-dark.png](us29-overview-dark.png) |

US5 (process actions): spec 018 shipped them (its T029 spike passed), so the *Processes* view offers
*Suspend*, *Resume* and *Terminate* (typed pid). They are exercised end to end by spec 018's
quickstart scenario 11; this e2e suite does not terminate processes on the shared dev instance.

## Clean-up (T031)

After the runs: 0 flows named `Check: …` or `us29-…`, 0 schedules, 0 process-action records, no
`SentaiE2EDemo` role and no `e2e_*` user. The monitor alert raised by the backend suite
(`ERROR #7823` from existing dispatch tests) was cleared with `$SYSTEM.Monitor.Clear()`.
