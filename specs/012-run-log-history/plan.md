# Implementation Plan: Run Log and Run History

**Branch**: `feat/spec012` (feature dir `012-run-log-history`) | **Date**: 2026-09-28 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (5 clarifications, 15 FRs, 6 SCs). Backend: one new narrator class
that writes log entries at the points where the run already decides or observes something, and a
paged run list. Frontend: a *Runs* screen, a chronological log panel, *Run history* on the flow
menu, and *Export*. The API changes additively ([contracts/api-delta.md](contracts/api-delta.md)).

## Summary

1. **Narrator (US1).** `sentai.dispatch.RunNarrator` owns every log message (text catalog in
   [data-model §2](data-model.md)). It is called from the places that already own the facts:
   `WaveDispatcher.CreateRun` (dispatched), `StepRun.TransitionTo` (every state change, with the
   previous state and the duration), `ComputeEligibleSteps` (join blocked, naming the failed
   input), `WaveDispatcher.MarkTargetFailed` / a new `MarkTargetAnswered` (outage start/end,
   deduplicated), `RenewRunCredentialIfDue` (refused renewal), `FinalizeRun` (outcome and counts),
   and the REST handlers for cancel, pause and re-run (who asked, and the refusal verbatim).
   Every call is wrapped so a failed write never changes the run (FR-004).
2. **Ordering fix.** `LogEntry.at` gets millisecond precision, and the read orders by
   `at DESC, %ID DESC`, so entries written in the same second keep their order.
3. **Paged run list (US2).** `GET /runs` implements the contract's `limit` (default 50, max 200)
   and adds `state` and `before` (a stable cursor: the run's row id, `seq`). Each item gains
   `seq`, `flowName`, `totalDurationMs` and `stepCounts`, computed for the page with two grouped
   SQL queries. A platform SQL refusal (`SQLCODE -99`) is returned as 403 verbatim.
4. **Runs screen (US2).** A fourth tab, *Runs* (`?view=runs&flow=&state=`), lists pages, filters
   and "Load more". Opening a run uses the existing run view. When the run is terminal, the view
   is read-only (it already hides the controls), and *Back to runs* replaces *Back to flow* when
   the address says `from=runs`. The flow menu (*More*) gains *Run history*.
5. **Log panel (US1).** The view renders the log in time order (reversing the API's newest-first
   order), keeps the newest entry visible while live, marks severity by a text label plus colour,
   and explains an empty log of a pre-feature run.
6. **Export (US3).** Pure `buildRunExport(detail, flowName, now)` → JSON; a tiny download edge
   (`Blob` + anchor) in the component.

## Technical Context

**Language/Version**: ObjectScript (IRIS 2026.2) for the backend; TypeScript 5.9 + Svelte 5 for
the canvas.

**Primary Dependencies**: none new.

**Storage**: `sentai.model.LogEntry` (exists). `at` changes from seconds to milliseconds
(`$ZDATETIME($ZTIMESTAMP,3,1,3)` is UTC; the product's other times are local `$HOROLOG`, so the
narrator uses `$ZDATETIME($NOW(),3,,3)`, local time with milliseconds, for consistency with step
times). No new class is persisted. Outage flags use the existing
`^IRIS.Temp.sentaiTargetCred(run,"%failAt",target)`.

**Testing**:
- IRIS `%UnitTest`: `RunNarratorTest` (message catalog, dedupe, never-throws), additions to the
  dispatcher tests (each hook writes its entry), `RunListTest` (paging, filters, counts, 403).
- vitest: `runs.ts` (query ↔ address, page merge without duplicates, summary formatting),
  `log.ts` (ordering, severity labels, empty-log text), `export.ts`.
- Playwright: `us24-run-log.spec.ts`, `us25-run-history.spec.ts`, `us26-run-export.spec.ts`.

**Target Platform**: as today (IRIS container; Chromium for e2e).

**Project Type**: web application.

**Performance Goals**: SC-004: first page in < 1 s with 5,000 runs. The page query is
`SELECT TOP :limit … WHERE %ID < :before ORDER BY %ID DESC` on the id index, plus two grouped
queries over at most 200 run ids. The spec 010 measurement (4,962 flows listed in 60 ms) suggests
a large margin. T001 seeds 5,000 runs on an isolated namespace copy to measure it.

**Constraints**: additive API only (existing clients keep working: `GET /runs` still returns an
array); platform text verbatim; the top bar must still fit at 1440 px with four tabs; UI text in
English.

**Scale/Scope**: backend: 1 new class, ~8 hook lines, `ListRuns` rewrite, 3 test classes (~25
tests). Frontend: 1 screen, 3 pure modules, ~4 touched components. Unit tests +~30; e2e +~9.

## Constitution Check

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | The narrator is application-level: it receives facts and writes `LogEntry` through the model. REST handlers call it only for operator requests, which only they observe. The canvas: `RunsScreen` → pure `runs.ts`/`log.ts`/`export.ts`; HTTP only in `api/client.ts`. | ✅ |
| **II Closed Capability Set** | No new operation; `GET /runs` gains declared query parameters, validated (limit range, state enum, numeric cursor). Log messages are fixed templates filled with data; nothing is evaluated. | ✅ |
| **III Delegated Authorization** | Runs are read with the operator's SQL privileges; a refusal is 403 with the platform's text. Refusals of cancel/pause/re-run are logged verbatim. No owner filter is invented. | ✅ |
| **IV Errors as Values** | The narrator returns `%Status` and every call site ignores it after recording nothing else (FR-004); `ListRuns` returns problems as values. Frontend: `ApiResult` for the list, tagged states in the screen. | ✅ |
| **V Verifiable Increments** | Four increments (log, list API + screen, history entry points, export), each with a failing e2e first. Dependency: the *Runs* screen needs the list API delta; export needs nothing else. | ✅ |
| **VI Technology Agnosticism** | Only in plan/research. | ✅ |
| SOLID / SoC | Message wording lives only in `RunNarrator`; deciding when to log stays where the fact is known. | ✅ |
| TDD | Failing tests first in every task group. | ✅ |
| YAGNI | No retention, no log search, no text export, no SSE change. | ✅ |
| Reproducibility | Unchanged. | ✅ |

## Decisions

- **D-1 Where each entry comes from.** See [data-model §2](data-model.md) for the full table.
  The rule: the fact is logged by the code that establishes it, through one narrator method.
- **D-2 Transition entries inside the transition's transaction.** `TransitionTo` calls
  `RunNarrator.StepChanged(me, from, to)` after `%Save` and before `TCOMMIT`, inside its own
  `Try`: an exception in the narrator is swallowed there, so the state change commits anyway
  (FR-004). The run's `eventVersion` is bumped once for the transition. `LogEntry.Append` bumps
  it again, which is harmless: pollers only compare it.
- **D-3 Target outage dedupe.** `MarkTargetFailed` logs "stopped answering" only when no
  `%down` flag exists for (run, target), then sets it. `MarkTargetAnswered` (called where a
  target call succeeds: `PollInFlightSteps`, `ExecuteStepAsync`, `RenewTargetCredentialsIfDue`)
  logs "answers again" only when the flag exists, then kills it (SC-006).
- **D-4 Operator requests.** `CancelRun`, `PauseRun`, `CancelStep`, `PauseStep` and `RerunStep`
  handlers in `rest/Dispatcher.cls` call `RunNarrator.Requested(runGuid, stepId, user, action,
  refusalText)` after the operation's outcome is known: one entry, *info* when accepted and
  *warning* with the verbatim text when refused.
- **D-5 Join blocked.** `ComputeEligibleSteps` already knows which sources failed; it passes the
  first failed or cancelled source's id to `RunNarrator.JoinBlocked`. The step's own
  `failureReason` stays "One or more required inputs failed" (existing contract). The log adds
  which input.
- **D-6 Paged list.** `GET /runs?flowId=&state=&limit=&before=`. `limit` is 1–200 (default 50);
  otherwise 400 with `code: LIMIT_OUT_OF_RANGE`. `state` must be one of the four run states
  (otherwise 400 `STATE_UNKNOWN`). `before` is a positive integer (otherwise 400
  `CURSOR_INVALID`). Items are ordered by `seq` descending; the next page is `before=<last seq>`.
  The response stays a JSON array, and each item is a `RunSummary`
  ([contract](contracts/api-delta.md)).
- **D-7 Screen and address.** `Screen` gains `'runs'`. Address: `?view=runs[&flow=<id>][&state=<s>][&pageSize=<n>]`
  (`pageSize` 1–200, default 50, passed as `limit`; it lets the e2e test paging with few runs).
  Opening a run from the list pushes `?run=<guid>&from=runs&flow=<id>[&state=]`, so *Back to
  runs* restores the filters. The fourth tab must fit at 1440 px next to the flow actions; if it
  does not, the tab labels shrink per spec 009's spacing rule ([R-3](research.md)).
- **D-8 Read-only run view.** The view already disables *Pause*/*Cancel wave* and hides *Re-run*
  for terminal runs (`RunScreen` `live`, `RunNode` `runLive`). No change beyond the back button.
- **D-9 Log panel.** `log.ts`: `chronological(log)` reverses the API order (newest-first, ties
  already broken by id). The panel scrolls to the end on new entries while live, unless the
  operator scrolled up. Severity shows as `INFO`/`WARN`/`ERROR` text plus the existing colour
  classes. An empty log shows "No log was recorded for runs before this version."
- **D-10 Export.** `export.ts`: `buildRunExport(detail, flowName, now)` returns `{format:
  "sentai-run-export/1", exportedAt, exportedWhile?, flow: {id, name, revision}, run: {...},
  steps: [...], log: [chronological]}`. The file name slugifies the flow name
  (`[^A-Za-z0-9._-]` → `-`). Nothing from the session is read (FR-014).

## Increments

| # | Story | First failing test | Then |
|---|---|---|---|
| 1 | US1 log (backend) | `RunNarratorTest`; dispatcher hook tests; `us24` (example run log order and content) | narrator, hooks, ordering fix |
| 2 | US1 log (panel) | `log.test.ts`; `us24` panel assertions | chronological panel, empty-log text |
| 3 | US2 list API | `RunListTest` | `ListRuns` rewrite, contract delta |
| 4 | US2 screen | `runs.test.ts`; `us25` | *Runs* tab, filters, paging, back to runs, *Run history* |
| 5 | US3 export | `export.test.ts`; `us26` | *Export* button |

## Project Structure

### Documentation (this feature)

```text
specs/012-run-log-history/
├── plan.md  research.md  data-model.md  quickstart.md  analysis.md  tasks.md
├── contracts/api-delta.md
└── checklists/requirements.md
```

### Source Code

```text
src/sentai/dispatch/RunNarrator.cls           # new
src/sentai/model/LogEntry.cls                 # ms timestamps
src/sentai/model/StepRun.cls                  # TransitionTo → narrator
src/sentai/dispatch/WaveDispatcher.cls        # hooks: CreateRun, ComputeEligibleSteps, targets, renewal, FinalizeRun
src/sentai/rest/Dispatcher.cls                # ListRuns paged; control handlers → narrator; log order tiebreak
tests/sentai/unittest/RunNarratorTest.cls     # new
tests/sentai/unittest/RunListTest.cls         # new
frontend/src/lib/runs/RunsScreen.svelte       # new
frontend/src/lib/runs/runs.ts (+ test)        # new
frontend/src/lib/run/log.ts (+ test)          # new
frontend/src/lib/run/export.ts (+ test)       # new
frontend/src/lib/run/RunScreen.svelte         # panel, back to runs, export
frontend/src/lib/shell/TopBar.svelte          # Runs tab, Run history
frontend/src/lib/shell/screen.ts              # 'runs'
frontend/src/lib/api/client.ts, wire.ts       # listRuns(query)
frontend/src/routes/+page.svelte              # wiring
frontend/tests/us24-run-log.spec.ts, us25-run-history.spec.ts, us26-run-export.spec.ts
specs/002-canvas-ui/contracts/openapi.yaml    # RunSummary, query params (additive)
README.md                                     # Logs row, How to use: Runs
```

## Complexity Tracking

No violations.

## Constitution re-check after Phase 1

Still passing. The only new server behaviour is writing records of facts the product already
establishes; nothing about permissions is inferred or stored.
