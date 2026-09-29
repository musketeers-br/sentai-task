# Data Model: Instance Overview API

**Feature**: 018-instance-overview-api | **Date**: 2026-09-29

Only §5 is stored. Everything else is computed per request from the platform's answers and
returned; nothing is cached (FR-003).

## 1. Area

A fixed, compiled list (Constitution II). The `id` is the only thing a request may name.

| id | group | reading | summary read(s) | step type (area → flow) |
|---|---|---|---|---|
| `processes` | instance | yes | processes | — |
| `locks` | instance | yes | locks | — |
| `memory` | instance | yes | shared-memory | — |
| `activity` | instance | yes | dashboard/main | — |
| `devices` | instance | yes | devices | — |
| `licenses` | instance | yes | license-usage | — |
| `web-sessions` | instance | yes | web-sessions | — |
| `security` | report | no | security/users | `security-posture-report` |
| `web-apps` | report | no | web-apps | `web-app-inventory` |
| `alerts` | report | no | dashboard/main (shared) | `system-alerts-check` |
| `secrets` | report | no | wallet/collections | `secrets-inventory` |

Rules: an id outside this table → `404 UNKNOWN_AREA` / `UNKNOWN_READING` with no platform call. The
catalog is not changed (clarification Q4); the step type column must name an existing
`platform-read` entry, checked by a unit test.

## 2. Reading (response of `GET /overview/readings/{id}`)

```text
Reading {
  area:     string            // §1 id
  readAt:   string            // ISO 8601 UTC, when the product finished the platform reads
  columns:  string[]          // allow-listed field names, in display order
  rows:     object[]          // each row has exactly `columns` (absent field → null, never 0)
  computed: string[]          // names of columns the product computed (e.g. "SMHUsedPercent")
  parts?:   { [name]: object } // activity only: "systemUsage", "dashboard" (allow-listed objects)
}
```

Allow-lists (research R-4; anything else is dropped):

- **processes**: `Pid, Job, Username, OSUserName, Nspace, Routine, State, Commands, Globals,
  CPUTime, ElapsedTime, Device, ClientName, IPAddress, EXEname, ParentPid, CanBeExamined,
  CanBeSuspended, CanBeTerminated, CanReceiveBroadcast`
- **locks**: `Pid, ModeCount, Reference, Directory, System, Removable, RemoteOwner, RoutineInfo,
  OSUserName` (no `DeleteID`)
- **memory**: `Description, SMHAllocated, SMHAvailable, SMHUsed, SMTUsed, GSTUsed, AllUsed` +
  computed `SMHUsedPercent` = `round(SMHUsed / SMHAllocated × 100, 1)` when `SMHAllocated > 0`,
  else null
- **activity**: `rows` = `system-resources` rows `Name, Seize, Nseize, Aseize, Bseize, BusySet`;
  `parts.systemUsage` = `AllGlobalReferences, GlobalUpdateReferences, RoutineCalls,
  RoutineBufferLoadsAndSaves, LogicalBlockRequests, BlockReads, BlockWrites, WIJwrites,
  JournalEntries, JournalBlockWrites, RoutineLines, LastUpdate`; `parts.dashboard` =
  `{performance, status, systemUsage}` where `performance` = `GlobalRefsPerSecond, GlobalRefs,
  GlobalSetKill, RoutineRefs, LogicalRequests, DiskReads, DiskWrites, CacheEfficiency`, `status` =
  `UpTime, LastBackup, SystemMonitor`, `systemUsage` = `DatabaseSpace, DatabaseJournal,
  JournalSpace, JournalEntries, LockTable, WriteDaemon, Processes, CSPSessions` plus
  `BusyProcesses` as an array of `{Process, Commands}`
- **devices**: `Name, PhysicalDevice, Type, SubType, Description, Alias, AlternateDevice`
- **licenses**: `rows` = `UsageByProcess` rows `PID, Process, LID, Type, Con, MaxCon, CSPCon, LU,
  Active, Grace`; `parts.summary` = `Summary` rows `LicenseUnitUse, Local, Distributed`;
  `parts.byUser` = `UsageByUser` rows `UserId, Type, Connects, MaxCon, CSPCon, LU, Active, Grace`;
  `ConnectionList` is not returned
- **Nested objects follow the same rule**: every object inside a reading, at any depth, is copied
  field by field from a list above; an object or array the list does not name is dropped.
- **web-sessions**: `Username, Application, Timeout, Preserve, LicenseId, SesProcessId,
  AllowEndSession` (no `ID`)

## 3. Summary (response of `GET /overview`)

```text
Summary {
  readAt: string
  areas:  AreaEntry[]          // always 11, in §1 order
}
AreaEntry {
  area:     string             // §1 id
  group:    "instance" | "report"
  outcome:  "ok" | "refused" | "unreachable"
  readAt:   string
  headline: object | null      // when ok — fields of research R-3
  problem:  Problem | null     // when not ok
  stepType: string | null      // §1 last column; null = cannot become a flow
}
Problem {                      // TaskService.Problem shape, unchanged
  title, detail: string
  httpStatus: number           // the platform's; 0 → outcome "unreachable"
  platformStatus?: object      // the platform's status object, verbatim
}
```

Rules: one entry's outcome never changes another's (FR-007); a 200 whose `status.errors` is not
empty is `refused` (edge case); the summary itself answers 200 whenever the product's own token check
passed.

## 4. On-demand report (response of `POST /overview/reports/{stepType}`)

```text
OnDemandReport {
  stepType:      string
  state:         "completed" | "failed"     // as StepRun.state for the same Build outcome
  failureReason: string                     // "" when completed; the Build error text verbatim
  report:        object | null              // spec 013 plan D-4 shape, not truncated
  ranAt:         string
}
```

Request body: `{ "parameters": { … } }` (optional). Parameter errors → 422 with the validator's
`{errors, warnings}` (codes `PARAM_*`), no platform call.

## 5. ProcessAction (stored; User Story 5 only, clarification Q3)

Persistent class `sentai.model.ProcessAction`, append-only (no update or delete method is exposed).

| Property | Type | Rule |
|---|---|---|
| `at` | %TimeStamp (UTC) | set on save |
| `operator` | %String(128) | `Dispatcher.CurrentUser()` |
| `pid` | %Integer | the request's path pid, > 0 |
| `action` | %String | `suspend` \| `resume` \| `terminate` |
| `httpStatus` | %Integer | the platform's; 0 when it did not answer |
| `accepted` | %Boolean | `httpStatus` 2xx and no `status.errors` |
| `platformStatus` | %String(MAXLEN="") | the platform's status object as JSON, verbatim |

Index on `at` for "newest first". A request refused for missing or wrong confirmation (428) never
reaches the platform and writes no row. Nothing in this record is ever read to decide whether a later
action is allowed (Constitution III).

## 6. Area → flow (request/response of `POST /overview/areas/{area}/flow`)

Request `{ "parameters": { … } }` (optional). Response 201:

```text
{ flow: <ShapeFlow of the new flow, as POST /flows>, validation: <FlowValidator.Validate report> }
```

Built by `sentai.overview.AreaFlow` (application); structural validation and the response shape
stay in the REST handler (Constitution I). Definition (research R-8): name `Check: <catalog label>` (+ ` (n)` when taken), `defaultCategory`
and step `wqmCategory` = `Default` if listed else first listed category, one step `"01"` of the
mapped type, `taskName` = catalog label, `namespace` `%SYS`, the supplied parameters, geometry
`{"01": {x: 40, y: 160}}`. Area without a step type → 409 `AREA_HAS_NO_STEP_TYPE`, nothing created.
