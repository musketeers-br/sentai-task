# Spec 013 — Evidence

| File | Task | What it shows |
|---|---|---|
| [t001-reads.md](t001-reads.md) | T001 | Wallet answer shapes (no value ever returned), privileges, and what `SeriousAlerts` counts (not reset by `Monitor.Clear`, reset by a restart) |

## Baseline (T002)

After spec 012: backend 299/299, unit 178/178, e2e 72 passed / 3 failed (explained in spec 012's
evidence) / 1 opt-in skipped.

## After spec 013

- Backend: **322/322** (+ `ReadExecutorTest` 7, `ReportSystemAlertsTest` 5, `ReportSecurityTest` 9,
  registry cases 2; catalog tests updated from 9 to 13 types).
- Unit: **184/184** (+ `result` 5, palette groups 1; the theme audit counts 53 colour pairs with the
  two new category colours).
- E2e `us27-area-steps`: **4/4** — palette groups; the three reports locally and on `iris-target`
  with findings first in the *Result* panel; the alerts gate (the dev instance had 5 serious
  alerts since its restart, so the check failed and the join kept step 02 from starting, with
  the log naming the input); a database size report's result readable in the canvas.

## Full regression (T018, 2026-09-29)

E2e full suite: **78 passed, 1 failed, 1 opt-in skipped** (80). The failure is `us19 duplicated
tab`, which predates specs 011–013 (spec 011 evidence). Backend 322/322, unit 184/184.

## Cleanup (T021)

The `us24-`…`us27-` flows the regression created were deleted with their runs through
`sentai.demo.Demo.DeleteFlow`.
