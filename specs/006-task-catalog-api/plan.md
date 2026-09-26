# Implementation Plan: Task Catalog API (backend)

**Branch**: `006-task-catalog-api` | **Date**: 2026-09-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/006-task-catalog-api/spec.md`. This plan covers the
backend only; the UI is spec 007.

## Summary

The three existing catalog calls (list, item read, suspend/resume) are changed so that every value
they return about a task is the platform's own value, read with the operator's token, or is absent.

Phase 0 on the real instance ([research.md](research.md)) settled the source. It is the
**management API**: list for ids, single read for class and run-as user, info read for status and
times. The in-process path is rejected because it skips the platform's task privilege. An operator
without `%Admin_Task` read and suspended tasks that way.

Phase 0 also found that the platform's list read is lossy. Every suspended task comes back
`Suspended:false`, and `NextScheduled` is truncated. So the product's current `suspended` flag and
filter never worked, and its suspend call hits a 404 path.

The corrected design:

- per-task single and info reads, 0.38 s for 151 tasks;
- the proven `task/suspend` and `task/resume` calls, each followed by a re-read;
- SentaiTask origin taken from the name grammar the product itself generates;
- destructiveness from the step-type catalog;
- filters over the corrected values;
- the last 5 executions from the proven history read, on the item read only.

There is no new endpoint, no persistence and no flow-schema change.

## Technical Context

**Language/Version**: ObjectScript, InterSystems IRIS 2026.2 (Build 221U)

**Primary Dependencies**: IRIS management API `/api/admin/v2` (`tasks`, `task`, `task/info`,
`task/history`, `task/suspend`, `task/resume`) via `sentai.dispatch.AdminApiClient`;
`sentai.registry.StepType` (catalog); `sentai.model.Flow` / `Step` (origin);
`$SYSTEM.Status.GetErrorText` (platform decoding of `Status`)

**Storage**: none new (read-only view; product tables read with parameterized SQL only)

**Testing**: `%UnitTest` via `zpm "test sentai-task -only"`; `sentai.unittest.AdminApiDouble` scripts every
platform read, keyed by full URL for GET and by base path for POST, with the full URL recorded;
quickstart script against the container for SC-001…SC-005

**Target Platform**: container `sentai-task-iris-1`, namespace `IRISAPP`

**Project Type**: web-service backend (REST API consumed by the canvas)

**Performance Goals**: full list < 2 s for ~150 tasks (SC-005). Measured platform cost is 0.38 s,
done sequentially (R-2)

**Constraints**: no new endpoint; no flow-schema change; no create, edit, delete, run-now or
schedule change (spec 004 D-2); no test removed; ~5 tasks

**Scale/Scope**: 1 service class rewritten, 3 small classes added, 2 methods touched in
`Dispatcher`, 1 helper plus 1 data fix in `StepType`; ≈ +40 backend tests, 2 adjusted

No NEEDS CLARIFICATION remains; every unknown was closed by R-1…R-5.

## Constitution Check

*GATE: checked before Phase 0 and again after Phase 1.*

| Principle | How the design complies | Status |
|---|---|---|
| **III Delegated Authorization** | Every read, suspend and resume is a management-API call made with the **requesting operator's** bearer token. Nothing is cached across requests, and no permission is inferred. The in-process path was rejected **because** it bypasses `%Admin_Task` (R-1: an unprivileged `spk6op` read tasks and suspended task 1003). Refusals are returned verbatim, with the platform's HTTP status and `platformStatus` object. This applies to the whole call (list refused) and to each task (`unavailable[]`, FR-009). The empty 403 body of 2026.2 is passed on as is, with nothing added. | ✅ |
| **II Closed Capability Set** | The platform paths are fixed strings. The task id is validated as a positive integer before it goes into `?id=`. Filters are data compared in memory. No SQL is built from input; the only SQL is `Flow.%ExistsId` and one parameterized `SELECT type FROM sentai_model.Step WHERE flow = ? AND id = ?`. There is no class or method name taken from input, no `$CLASSMETHOD` on input and no `Xecute`. Unknown `filter`/`destructiveOnly` values → 400. The origin regex runs on platform data through `$MATCH`, which evaluates nothing. | ✅ |
| **IV Errors as Values** | Each platform read returns `{httpStatus, result, status}` as a value, and a failed read becomes an `unavailable` entry, never an exception. The service returns an outcome object that `Dispatcher` maps to HTTP. A platform 200 that did not change the state is reported as `502 SUSPEND_NOT_APPLIED` rather than as success. | ✅ |
| **I Layered Architecture** | `Dispatcher` only parses and maps HTTP. `TaskService` orchestrates. `TaskShape`, `TaskOrigin` and `TaskFilter` are pure mapping and rules. `AdminApiClient` stays the only edge to the platform. The catalog stays the only source of destructiveness. | ✅ |
| **V Verifiable Increments** | Each of the 5 tasks ends in behaviour visible over REST, with its test written first. | ✅ |
| **Engineering: TDD / YAGNI / SoC** | Tests come first, against the double. There is no concurrency (it is not needed, R-2), no `LeaveInQueue` option, and no "not supported" branch (the contract is proven). | ✅ |
| **Handoff constraints** | No `Xecute`; no `MatchRoles:"%All"`; no new or unauthenticated web app; no AI in the core; no credential in code, fixtures or evidence (spike users had IRIS-generated passwords, never printed, and evidence redacts headers). No confidential product, company or programme names. | ✅ |

**Post-design re-check (after Phase 1)**: unchanged, all ✅. No Complexity Tracking entries.

## Decisions

- **D-1 — Read source is the management API (R-1).** The list gives `Id`, `Name` and `Namespace`
  only. The single read gives `TaskClass`, `RunAsUser` and `TimePeriod`. The info read gives
  `Status`, `Error`, `LastStarted`, `LastFinished`, `NextScheduled` and `Suspended`. There are
  1 + 2N sequential calls on one token, and history is read on the item read only.
- **D-2 — Field semantics (R-5).** Values are verbatim. `status` is the platform's own text for
  its serialized `%Status` (it equals history `Status` and `DisplayStatus`). `lastError` is the
  info `Error` value unchanged, including `"Success"`. `suspended` comes from info, never from the
  list. `nextRun` stays as the platform gives it, even when the task is suspended.
- **D-3 — Suspend/resume (R-3).** `POST /v2/task/suspend?id=` or `/v2/task/resume?id=` with
  body `{}`, then a re-read. If the re-read does not show the requested state →
  `502 SUSPEND_NOT_APPLIED`. The platform returns 200 even when `Suspend()` fails internally.
- **D-4 — Correct one false catalog value.** The `purge-audit-records` `class` is changed from
  `%SYS.Task.PurgeAuditDatabase` (not compiled on 2026.2) to `%SYS.Task.PurgeAudit`, which is the
  platform's own audit-purge task class (R-5 / Other facts). Without this, US-1 scenario 3 ("audit
  purge → destructive") cannot pass. `available` stays `false`, so no execution path changes. The
  wrong `compact-globals` and `defragment-globals` class names are out of scope; they are listed
  in the README.
- **D-5 — Destructiveness and origin.** Rules are in
  [data-model.md](data-model.md#destructiveness-fr-004): catalog class → known; the product's own
  `ScheduledFlowTask` → the step's type; anything else → `destructiveUnknown`. The origin grammar
  is `^SentaiTask: ([1-9][0-9]*)#([0-9A-Za-z_-]{1,8})$`, derived from the generator and the flow
  schema rather than from the draft `\d{2,}`.
- **D-6 — Filters.** "Scheduled" means not suspended according to info. A task whose `suspended`
  or `destructive` value is unavailable or unknown is excluded from those filters. The count stays
  in the existing `{total, matched, items}` envelope, so there is no break.
- **D-7 — History (R-4 proven → US-5 in).** Up to 5 rows whose `Routine` equals `class`, with the
  platform keys, no computed duration, on the item read only.

## Spec deviations (to be reflected in the spec at `/speckit-tasks` time)

| Spec text | Platform fact | Plan |
|---|---|---|
| US-3 / Independent Test: a suspended task "no longer shows a next run" | A suspended task keeps `NextScheduled` (R-3) | SC-004 is judged on `suspended` only; `nextRun` is returned verbatim |
| FR-006 fallback "not supported on the target platform" | The contract is proven | The fallback is not built |
| US-1 scenario 3 "audit purge is destructive" | The catalog named a class that does not exist | D-4 |
| FR-010 "only `state` and `className` removed" | — | Honoured: `isDestructive` and `lastRun` are kept as deprecated aliases carrying corrected values |
| (new) invalid filter values | — | 400 `INVALID_FILTER` (input validated as data, Constitution II) |

## Project Structure

### Documentation (this feature)

```text
specs/006-task-catalog-api/
├── spec.md
├── plan.md               # this file
├── research.md           # Phase 0: R-1…R-5 with verbatim platform output
├── data-model.md         # catalog task, destructiveness, origin, filters, recent runs
├── quickstart.md         # (a)…(f) acceptance on the real instance
├── contracts/api-delta.md
├── checklists/requirements.md
├── evidence/             # written by quickstart (task 5)
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root)

```text
src/sentai/
├── catalog/TaskService.cls     # REWRITE: List, Read, SetSuspended; outcome values; platform reads
├── catalog/TaskShape.cls       # NEW, pure: reads → catalog task; unavailable[]; Status decoding
├── catalog/TaskOrigin.cls      # NEW: grammar ($MATCH), flowExists, step type (parameterized SQL)
├── catalog/TaskFilter.cls      # NEW, pure: parameter validation + Matches(task)
├── registry/StepType.cls       # + DestructiveByClass(class, .known); D-4 class fix
└── rest/Dispatcher.cls         # ListCatalogTasks / ReadCatalogTask / SuspendCatalogTask: map outcomes → HTTP

scripts/catalog-evidence/compare.sh   # NEW (task 5): quickstart (a) evidence generator

tests/sentai/unittest/
├── rest/CatalogTasksTest.cls          # ADJUST 2 tests (old list-only script; old suspend path)
├── catalog/TaskReadTest.cls           # NEW (task 1)
├── catalog/TaskOriginDestructiveTest.cls  # NEW (task 2)
├── catalog/TaskFilterTest.cls         # NEW (task 3)
├── catalog/TaskSuspendTest.cls        # NEW (task 4)
├── catalog/TaskHistoryTest.cls        # NEW (task 5)
└── registry/StepTypeTest.cls          # + DestructiveByClass, + D-4 class
```

**Structure Decision**: the existing single-project layout, with the catalog concern kept in
`sentai.catalog`. The pure classes (`TaskShape`, `TaskFilter`, the grammar in `TaskOrigin`) are
tested without the double. `TaskService` is tested through `AdminApiDouble` with every read
scripted. `Dispatcher` stays a thin mapping layer.

## Implementation Sequence (input to /speckit-tasks)

Every task is test-first. `TaskService.cls` and `Dispatcher.cls` are touched sequentially
(1 → 4 → 5).

| # | Task | FR / SC | Depends | Parallel |
|---|---|---|---|---|
| 1 | **Corrected read + field mapping + partial reads.** Test first, with the double scripting list, single and info. The tests cover each field's source; `status` for OK, a serialized error and a passthrough; `lastError` `"Success"` verbatim; `suspended` from info while the list says false; a single-read failure → `unavailable` with class and run-as user absent; an info-read failure → 6 fields absent; a list refusal (403) → whole call 403 with `platformStatus`; the item read equals the list item; item read 404 verbatim; a non-integer id → 404 with no platform call. Adjust the 2 existing `CatalogTasksTest` tests. | FR-001–003, FR-009, FR-010 | — | — |
| 2 | **Destructiveness + SentaiTask origin.** Test first: valid names (`1#01`, `12#a1`, `3#7`); a table of near-misses (see data-model) → no origin; flow deleted → `flowExists:false`; catalog class → known (`%SYS.Task.PurgeTaskHistory` → true); unknown class → `destructiveUnknown`; `ScheduledFlowTask` → the step's type, or unknown when the step or flow is missing; class unavailable → unknown. `StepType.DestructiveByClass` plus the D-4 fix, with `StepTypeTest`. | FR-004, FR-005 | 1 | `TaskOrigin` / `StepType` [P] with the task-1 tail |
| 3 | **Filters + count.** Test first: `q` on name, on class and case-insensitive; `namespace`; `scheduled` / `suspended` on the info value, with unavailable excluded; `destructiveOnly` excluding unknown; one combined case; `total`/`matched`; invalid `filter` / `destructiveOnly` → 400. | FR-007 | 1, 2 | `TaskFilter` pure → [P] with 2 |
| 4 | **Suspend/resume on the proven contract.** Test first: the suspend path and `{}` body are recorded by the double; the resume path; a re-read that shows the new state → 200 plus the task; a re-read that shows the old state → 502 `SUSPEND_NOT_APPLIED`; 403 verbatim (no re-read); 404 verbatim; a non-boolean `suspended` → 400. | FR-006, SC-004 | 1 | — |
| 5 | **History + docs + evidence.** Test first: execution rows only (`Routine = class`); at most 5, newest first; `[]` when there are none; absent and flagged when `class` or history is unavailable; never on list items. README: read sources and why not in-process (R-1, including the platform finding); what was proven and what was not (`%Admin_Operate` for reads; the catalog class names of compact/defragment); `lastError`/`status` semantics; the privilege the operator needs. Update the OpenAPI `CatalogTask` schema. `scripts/catalog-evidence/compare.sh`; run quickstart (a)–(f) and record the evidence. | FR-008, SC-001–005 | 1–4 | — |

**Cut order if time runs short**: first, the history part of task 5 (US-5): `recentRuns` stays
absent and the README says why. Next, the evidence polish of task 5, keeping the SC-001 script and
quickstart (a)–(e). Tasks 1, 2 and 4 are never cut.

**Note on tasks.md (after `/speckit-analyze`)**:
- The adjustment of `TestSuspendTogglesStateReflectedOnNextRead` belongs to the suspend task
  (tasks T005), not to row 1. The platform path it encodes only changes there.
- Row 1 stays a single task. Row 2's catalog helper is merged with its first use.
- The reason for both: Constitution V (observable increments) takes precedence over splitting by
  file count.

**Expected test count**: the backend suite is **122 today**, or the post-005 count if 005 lands
first. This feature adds **≈ +40** (task 1: 11, task 2: 10, task 3: 9, task 4: 7, task 5: 5,
StepType: 2 — estimate). It **adjusts 2** tests, both in `CatalogTasksTest`:
`TestNonProductTasksAppearAndAreFilterable` needs single and info scripted, and
`TestSuspendTogglesStateReflectedOnNextRead` encoded the unvalidated path
`/v2/tasks/<id>/suspend`. It **removes 0**.

Frontend: unit **48 → 48** and e2e **13 → 13**. `/catalog/tasks` has no frontend consumer, and
the frontend fixture that names `%SYS.Task.PurgeAuditDatabase` is local data, so the D-4 change
does not affect it.

## Risks

| Risk | Mitigation |
|---|---|
| A future platform fixes or changes the list's `Suspended` / `NextScheduled` | The product no longer reads those fields from the list, so a fix cannot break it |
| The serialized `%Status` changes form | The decoding is the platform's own function. Non-error values pass through unchanged. Quickstart (a) compares against the platform on every run |
| History mixes executions and admin events | The execution filter (`Routine = class`) rests on observed rows (R-4). Quickstart (f) re-checks it. If it fails, cut per the cut order |
| Another source names a task `SentaiTask: n#id` | FR-005 is name-based by spec. `flowExists` and the step lookup keep the claims about flows honest. Requiring `class = ScheduledFlowTask` for `origin` would need a spec change (noted, not adopted) |
| Token expiry (60 s, E-1) during a large list | The read takes < 0.5 s for 151 tasks. On expiry mid-list, the per-task 401s surface as `unavailable` with the platform's status, never as values |
| Platform refusal carries no reason (403 empty) | Passed on as is (Constitution III forbids adding one). The README names the privilege the platform checks, from its source code (not proven for `%Admin_Operate`) |
