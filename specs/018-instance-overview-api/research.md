# Research: Instance Overview API

**Feature**: 018-instance-overview-api | **Date**: 2026-09-29

All probes: dev container `sentai-task-iris-1` (IRIS 2026.2), `_SYSTEM`, read-only, one access token
per probe run, times from `curl -w %{time_total}` on the host (loopback). No credential is recorded
here. The platform's own description was saved from `GET /api/mgmnt/v1/%SYS/spec/api/admin`
(305 operations; `/api/admin` basePath).

## R-1 — Which platform reads make each reading

**Decision**: seven readings, each a fixed set of `GET` paths:

| Reading | Platform reads | Rows (dev) | Time | Bytes |
|---|---|---|---|---|
| `processes` | `/api/admin/v2/processes` | 65 | 68 ms | 17.8 kB |
| `locks` | `/api/admin/v2/locks` | 66 | 158 ms | 9.2 kB |
| `memory` | `/api/admin/v2/monitor/system-usage/shared-memory` | 28 | 21 ms | 3.6 kB |
| `activity` | `/api/admin/v2/monitor/system-usage` + `/api/admin/v2/monitor/dashboard/main` + `/api/admin/v2/monitor/dashboard/system-resources` | 1 + 1 + 56 | 12 + 73 + 24 ms | 6.2 kB |
| `devices` | `/api/admin/v2/devices` | 12 | 22 ms | 2.1 kB |
| `licenses` | `/api/admin/v2/monitor/license-usage` | summary + per process + per user | 49 ms | 5.9 kB |
| `web-sessions` | `/api/admin/v2/web-sessions` | 1 | 21 ms | 2.3 kB |

**Rationale**: every one answered 200 with `{status, console, result}`; none needs a parameter.
`activity` groups the three monitor reads because none of them alone answers "how busy is the
instance" and the seize counters are meaningless as a card of their own.

**Alternatives considered**: `GET /v2/process?id=<pid>` (single process, needs `id`, not `pid` —
`?pid=` answers 400 `ERROR #40300: Query parameter 'id' is required`) is kept for the process
actions' re-read (R-7), not as a reading. `/v2/monitor/dashboard/ecp` and
`/globals-and-routines` are left out (ECP is out of scope; the second is a per-global view).

## R-2 — What the API does not have

**Decision**: no reading, headline or label may say host CPU, host memory or console log.

**Rationale**: none of the 305 operations reports host CPU percentage, host RAM or
`messages.log`. The process rows do carry the platform's own per-process `CPUTime` and
`ElapsedTime`; those are shown under those names ("CPU time" of a process), which is the platform's
value, not a host measurement.

## R-3 — Summary headlines and their cost (clarification Q1)

**Decision**: the summary makes **10 distinct reads for its 11 areas** (the dashboard read serves
*activity* and *system alerts*), one after the other, and computes each headline from that one read:

| Area | Headline | From |
|---|---|---|
| processes | `count`; `busiest` = Pid, Routine, Commands of the row with most `Commands` | processes |
| locks | `count` | locks |
| memory | `usedPercent` of the `Total` row (`SMHUsed / SMHAllocated`); `mostUsed` = Description and percent of the consumer row with the highest share among rows with `SMHAllocated > 0` | shared-memory |
| activity | `uptime`, `lastBackup`, `globalRefsPerSecond`, `busyProcesses` (non-empty entries) | dashboard/main |
| devices | `count` | devices |
| licenses | `inUse`, `authorized` from `Summary` rows "Current License Units Used" and "License Units Authorized" (`Local`) | license-usage |
| web-sessions | `count` | web-sessions |
| security | `enabledAccounts` (`Enabled` true), `accounts` | security/users |
| web-apps | `count` | web-apps |
| alerts | `seriousAlerts`, `applicationErrors` from `Alerts` | dashboard/main (shared) |
| secrets | `collections` | wallet/collections |

Sum of measured times ≈ 0.57 s, far under SC-002's 3 s, with one 60 s access token (spec 001).

**Rationale**: running the four reports would add 1 + N + 2 reads for security alone (N enabled
accounts, capped at 200 by spec 013 R-3) and per-collection secret reads; Q1 chose counts. Reads in
series keep the code simple; parallel `%Net.HttpRequest`s would need workers for a 0.6 s total.

**Measured values on the dev container**: memory Total row 2,809,140 of 3,342,336 → 84 %; most used
consumer "Security System" 65,536 of 65,536 → 100 %; licenses 1 of 8 units; 7 of 9 accounts
enabled; 26 web applications; 1 wallet collection; 7 serious alerts, 0 application errors.

**Alternatives considered**: `dashboard/main.Licensing` (`LicenseUse` 13, `LicenseLimit` 8) counts
something different from license-usage's "Current License Units Used" (1) at the same moment; the
license-usage summary is the one the Management Portal's license page shows, so it is used, and the
disagreement is documented rather than reconciled.

## R-4 — Fields that must never leave the product (FR-016)

**Decision**: every reading copies only allow-listed fields (the `Report.Pick` rule of spec 013
D-5). Excluded on purpose:

- web-sessions `ID` — the session identifier is a bearer of the session; `LicenseId`,
  `Username`, `Application`, `Timeout`, `Preserve`, `AllowEndSession`, `SesProcessId` are kept.
- locks `DeleteID` — only needed to delete a lock, which is out of scope.
- the single-process read's `CSPSessionID` (R-7) — never copied.

**Rationale**: FR-016 forbids tokens; a CSP session id is one in practice. Allow-listing (not
deny-listing) means a field the platform adds later is dropped by default.

## R-5 — The platform-read helper to reuse

**Decision**: readings use `sentai.catalog.TaskService.PlatformRead(path, token)` →
`{httpStatus, result, status}` and `TaskService.Refusal(read)` → `{httpStatus, problem}` with
`platformStatus` verbatim, the outcome pattern `Dispatcher.WriteOutcome` already writes. On-demand
reports use `sentai.steps.reports.Reader` unchanged, because the report classes take it.

**Rationale**: those two helpers are the project's existing "refusal verbatim" edge
(Constitution III/IV) and are covered by tests; a third copy would drift. Moving them to a shared
class is a refactor the feature does not need.

**Alternatives considered**: `Reader.Get` for readings too — rejected: it returns only a text, and
the summary must return the platform's HTTP status and status object.

## R-6 — On-demand reports reuse the step's own code (FR-010)

**Decision**: `POST /overview/reports/{stepType}` validates parameters with
`FlowValidator.DeclaredStepFindings` and builds with `ReadExecutor.Build(type, parameters,
Reader.For("", token), .report)`, then answers `{state, failureReason, report}` exactly as a
`StepRun` stores it. No `StepRun`, `Run` or `LogEntry` is created. The report is not passed through
`FitResult`: it is not stored, so the 8,000-character limit does not apply.

**Rationale**: the same `Build` and the same parameter checks guarantee SC-004. `ReadExecutor.Build`
already refuses a type whose executor is not `platform-read` or whose class is not installed.

## R-7 — Process actions: what is known before the spike

**Decision**: User Story 5 starts with a spike (FR-019); nothing below is a contract yet.

- `POST /v2/process/suspend|resume|terminate` declare a body `payloadBody` of type `string`, no
  schema, response `200` or `default` — the body shape is unknown.
- Each process row carries the platform's own `CanBeSuspended`, `CanBeTerminated`,
  `CanReceiveBroadcast`, `CanBeExamined`. The product returns them as they are and never keeps a
  list of protected processes (US5 scenario 5).
- `GET /v2/process?id=<pid>` returns one process (`CommandsExecuted`, `CurrentDevice`, … and
  `CSPSessionID`, R-4) — the re-read after an action.

**Spike plan** (first task of US5): start a disposable process in `USER` (`JOB` of a hang loop),
then for each action try body shapes `{"pid": n}`, `{"Pid": n}`, `{"id": n}` and `?id=n`; record
request, status, body, and the process's state on re-read; repeat terminate as an operator without
`%Admin_Operate` to capture the refusal; write `evidence/NN-process-*.json` in spec 001's envelope.

## R-8 — Turning an area into a flow

**Decision**: the definition mirrors spec 010's example (`Demo.ExampleDefinition`): one step
`"01"`, the mapped type, `taskName` = catalog label, namespace `%SYS`, the supplied parameters,
`wqmCategory` = `Default` when the platform lists it, else the first category it lists; name
`"Check: <catalog label>"`, suffixed ` (2)`, ` (3)`… when the name exists (flow names are unique,
case-insensitive). `sentai.overview.AreaFlow` builds the definition (application layer); the REST
handler runs `Dispatcher.ValidateStructural` on it, `AreaFlow.Save` stores it with `Flow.SaveGraph`
and validates it with `FlowValidator.Validate(id, token)`, and the handler shapes the answer with
`Dispatcher.ShapeFlow`. The application class never calls `sentai.rest.*` (Constitution I).

**Rationale**: an ordinary flow, created by the same code path as `POST /flows`, cannot bypass any
rule (FR-015). `%SYS` is what the four report types default to (spec 013 D-10).

## R-9 — Target servers (FR-018)

**Decision**: any `target` in the query string or body of an overview request answers 400
`OVERVIEW_PRIMARY_ONLY` without a platform call.

**Rationale**: spec 008's remote path needs a per-target sign-in and its own timeouts; the overview
is primary-only in this version (spec Assumptions).

## R-10 — Test doubles

**Decision**: unit tests script the platform through `sentai.unittest.AdminApiDouble.Script(path,
method, status, location, body)`, as every REST and report test does; `^sentaiTestDouble` makes
`AdminApiClient` answer from the script. New tests live flat under
`tests/sentai/unittest/overview/`.
