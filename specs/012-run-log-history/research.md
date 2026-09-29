# Research: Run Log and Run History

## R-1 Why the log is empty today

- `sentai.model.LogEntry.Append` exists (spec 003) and `GET /runs/{guid}` returns `log`, but a
  search of `src/` finds **no caller** of `Append` (2026-09-28). The panel's "No log entries
  recorded for this run" is therefore shown for every run (spec 003 HANDOFF item 3).
- **Decision**: keep the entity and the read, and add the writer (the narrator).

## R-2 Ordering within one second

- `LogEntry.at` is written with `$ZDATETIME($HOROLOG,3)`, which has second precision, and the read
  orders by `at DESC` only. A fast in-process run (the spec 010 example ends in about 1 s) would
  write several entries in the same second in an undefined order.
- **Decision**: write `$ZDATETIME($NOW(),3,,3)` (local time, milliseconds; the same clock as step
  times) and order by `at DESC, %ID DESC`. Ids increase with insertion, so ties keep write order.

## R-3 A fourth tab at 1440 px

- Spec 009 tightened the top bar so three tabs and the flow actions fit at 1440 px, and spec 010
  added *More* and *Help*. A fourth label, "Runs", is 4 characters. **To measure in T012**: the
  existing top-bar fit test at 1440 px, with four tabs. If it clips, the fallback is to move
  *Targets* and *Runs* under one "Operations" menu. That fallback is not planned unless the test
  fails.

## R-4 Stable paging

- Run ids (`%ID`) increase monotonically with creation, like `startedAt`, but ids are unique and
  indexed. Paging by `before=<id>` never repeats or skips when new runs arrive (FR-008); offset
  paging would.
- The id is exposed as `seq` (an opaque number for the client). It is not a secret: runs are
  already addressed by guid, and `seq` gives nothing more.

## R-5 Counting steps per run cheaply

- One query per page:
  `SELECT run, state, COUNT(*) FROM sentai_model.StepRun WHERE run %INLIST :ids GROUP BY run, state`.
  Re-runs add step runs, so the count must use the **latest** step run per step, as the view does.
  The query is therefore over the latest attempt:
  `… WHERE ID IN (SELECT MAX(ID) FROM sentai_model.StepRun WHERE run %INLIST :ids GROUP BY run, stepId)`.
- **To measure in T001**: 5,000 runs × 4 steps, first page < 1 s (SC-004).

## R-6 Logging operator requests from the REST layer

- Cancel, pause and re-run are decided in `WaveDispatcher`, but only the REST handler knows who
  asked (`CurrentUser()`) and turns a refusal into the verbatim problem the operator sees.
- **Decision**: the handler logs, after the outcome is known, with the same text it returns
  (FR-002). The dispatcher's own transitions (for example `cancelled`) are logged by
  `TransitionTo` as for any change, so a cancel produces "cancel requested by X" followed by
  "#03 running → cancelled".

## R-7 Old runs

- 216 terminal runs exist on the dev instance with no log. There is no reliable "created by
  version" marker, and none is needed: a run dispatched after this feature always has at least the
  dispatch entry (unless that write failed, which FR-004 tolerates). The panel's text for an empty
  log therefore covers both cases truthfully: "No log was recorded for runs before this version."
