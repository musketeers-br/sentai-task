# Spec 012 — Evidence

## Baseline (T001)

Taken at the start of spec 012 (after spec 011): backend **284/284**, unit **161/161**, e2e 66
passed / 2 failed / 1 opt-in skipped (the us21 failure fixed in spec 011; `us19 duplicated tab`
predates both specs).

SC-004 (first page < 1 s with 5,000 runs) is met by construction and measured on the dev
instance: the page is `SELECT TOP n … WHERE r.ID < ? ORDER BY r.ID DESC` on the row id, plus one
grouped count over at most 200 run ids; `GET /runs?limit=50` answers in well under a second with
the instance's run history.

## Findings while implementing

- **The run log was unreadable, not only unwritten.** `at` is an SQL reserved word in IRIS
  (`SQLCODE -12` on `SELECT at …`). `GET /runs/{guid}` read the log with an unquoted `at`, so the
  read always failed silently and the panel would have been empty even with entries. Fixed by
  quoting the column (`"at"`), with a test that reads entries back in order.
- **Grouped states come back upper-case.** `GROUP BY state` returns the collated value
  (`COMPLETED`); the step counts normalise it to the API's spelling.
- **eventVersion is bumped once per change.** Entries that accompany a transition, a new run or
  the run's end are written without a second bump (`LogEntry.Append(…, bump=0)`), so the existing
  eventVersion guarantees and tests hold; standalone entries (operator requests, target outages,
  refused renewals, re-runs queued) bump as before.
- **Filters use their own address parameters.** `flow` already names the editor's open flow,
  which the page loads from the address; the Runs filters are `runsFlow` and `runsState`.
- **Four tabs fit at 1440 px** after tightening the top bar (tab padding 7 px, gap 6 px); the
  spec 010 fit test (`us21 top bar`) and `us25` both check it.

## Results

Recorded in T018 below once the full regression runs.
