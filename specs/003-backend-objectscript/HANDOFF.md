# HANDOFF — 003-backend-objectscript

## Objective
Implement the SentaiTask ObjectScript backend for persistence, validation, dispatch, and
tracking of flows defined by spec 002.

## Mandatory sources
- spec 003
- spec 002's openapi.yaml
- spec 002's data-model.md
- spec 002's flow-definition.schema.json
- spec 001's compatibility.md and decision.md

## Decisions already fixed
- Join policy v1: ALL_MUST_SUCCEED
- Scheduler via the native IRIS mechanism
- GUID via the native IRIS mechanism
- isDestructive derived from the type
- single instance in v1
- pause only for the purge family

## Technical constraints
- no unauthenticated web app
- no MatchRoles:"%All"
- no Xecute on request parameters
- no credentials in code
- preserve failureReason verbatim from IRIS

## Architectural expectation
- backend in pure ObjectScript
- full adherence to the approved contracts
- separation between persistence, validation, dispatch, API, and events
- solution prepared for decomposition into small, testable tasks

## Known risks
- the prior absence of this handoff may have left implicit assumptions
- integration decisions and namespace conventions may need adjustment
- SSE and asynchronous dispatch require technical validation on the target IRIS instance

## Points the plan must make explicit
- classes and namespaces
- persistence strategy
- REST strategy
- dispatch strategy
- SSE strategy
- transactions, concurrency, and recovery
- tests per layer

## Post-implementation validation findings

Validation of the implemented backend against the current spec and test suite exposed real backend
defects that had previously been masked by incorrect persistence and invalid test assumptions. The
following issues were fixed in code and corresponding tests were aligned to actual IRIS behavior:

- reference properties (`flow`, `run`) had been assigned raw ids, causing persisted relations to be
  stored as `0` and making flows appear to have no steps/edges during validation and dispatch
- bare `Throw` statements were rethrowing stale `$ZERROR` values instead of the actual failure
  status
- `XIndexOpen(...)` had been treated as returning an id, and in some cases used on non-unique
  indexes that do not generate an Open method
- `Join` queries failed because `Join` is a reserved SQL word and must be quoted
- `%request.Data(...)` had been used as if it were a method
- `%Get("%ID")` had been used without aliasing `%ID`
- scheduling had been written against `%SYS.Task.Definition` instead of `%SYS.Task`
- the read-only precondition probe did not actually touch the filesystem
- tests contained the same invalid IRIS assumptions as the code and were corrected accordingly

All 77 `sentai` tests pass after these fixes, and the suite was confirmed repeatable on IRIS 2026.2
without leaving scheduled tasks behind.

## Scope reduction decided after validation

Scheduled flows containing any destructive step are out of scope for v1 scheduling behavior.

Operational rule:
- `POST /flows/{flowId}/schedule` MUST refuse any flow that contains one or more destructive steps
- the refusal MUST be explicit and observable to the operator as a validation error
- no native scheduled task MUST be created for such a flow

Rationale:
- SC-006 requires typed confirmation before any destructive step starts
- the current scheduled execution path has no approved mechanism to satisfy that confirmation at
  fire time
- rather than inventing hidden authorization semantics, v1 reduces scope and blocks scheduling of
  destructive flows altogether

Implementation (2026-09-23): `sentai.validation.FlowValidator.ValidateForSchedule` = `Validate()`
plus one `DESTRUCTIVE_NOT_SCHEDULABLE` error per destructive step; `/schedule` blocks on it with
422 `ValidationReport` before any `%SYS.Task` is created. `/validate` and `/dispatch` keep calling
`Validate()`, so manual dispatch with typed confirmation is unchanged (SC-006 still enforced).

TD-06 evidence so far — in-process, on the real IRIS 2026.2 instance (`zpm "test sentai-task -v
-only"`, 81/81 passed, `ScheduleEndpointTest`, `DestructiveSchedulingRuleTest`):
- canonical flow (step 04 `purge-audit-records`) → `ScheduleFlow` status 422, body
  `{"errors":[{"stepId":"04","code":"DESTRUCTIVE_NOT_SCHEDULABLE","message":"Step type
  'purge-audit-records' is destructive; flows with destructive steps are not schedulable in v1 and
  must be dispatched manually with typed confirmation"}],"warnings":[]}`
- `%SYS.Task` count for the flow: 0; instance-wide `%SYS.Task` count unchanged; `scheduleSpec` not
  recorded on the flow
- same flow still dispatches manually with confirmation, and is refused (428 path,
  `CONFIRMATION_REQUIRED` naming 04) without it

Over HTTP (T073, 2026-09-23): `POST /csp/sentai/api/v1/flows/{id}/schedule` on the destructive
canonical flow → 422 with the payload above; `SentaiTask: <id>#` tasks 0, instance-wide `%SYS.Task`
count 16 → 16 ([`quickstart-evidence.md`](quickstart-evidence.md) step 9).

## Open implementation follow-up

The persisted `scheduleSpec` is not yet converted into the native `%SYS.Task` schedule fields
(`TimePeriod`/time configuration). This remains an implementation gap and must not be treated as
resolved scheduling behavior until validated and completed.

## Data sanitation required

Because earlier persistence bugs wrote orphaned records with `flow = 0`, the instance may contain
invalid historical data (`Step`, `Edge`, and possibly related entities) not attached to any valid
flow.

Required follow-up:
- perform a controlled cleanup before treating the environment as clean
- record counts and sample evidence before cleanup
- execute cleanup through a reviewable procedure, preferably backed by a script
- record counts and evidence after cleanup
- do not silently delete data without preserving an audit note of what was removed

Status (2026-09-23): procedure and tool in `scripts/sanitation/` (read-only `Report()`, guarded
`Apply()` with fingerprint sign-off, ZWRITE backup and audit entry). Pre-cleanup inventory on the dev
instance recorded in [`sanitation-evidence.md`](sanitation-evidence.md): 527 orphans (Step 266,
Edge 209, Join 52), all test-suite residue; the stored reference is empty (SQL `NULL`), not `0`.
Cleanup (T072) executed 2026-09-23 03:31:02 after sign-off on fingerprint `137624262-527`: 527 rows
removed, backup + audit entry `^sentaiOps("sanitation", 1)`, post-cleanup total 0, suite green.

## Real-instance verification (T070) — escalations

Full record: [`quickstart-evidence.md`](quickstart-evidence.md). Quickstart steps 1–10 pass over
HTTP after seven defects found on the real instance were fixed (work queue class, locks, empty POST
body, pause URL, lock-induced rollback of terminal transitions, SSE 500, SSE flushing). TD-01, TD-03
and TD-06 pass. Decisions needed:

- **E-1 (TD-01/TD-05)** The background dispatch job forwards the operator's 60 s access token and
  cannot refresh it: platform calls made more than ~60 s after dispatch return 401, so steps that
  start or finish later cannot be driven or observed.
- **E-2 (TD-02)** Only `integrity-check` is proven end to end. `defragment` exists; the assumed
  endpoints for `compact-globals`, `switch-journal`, `purge-audit-records`, `purge-task-history`
  and `custom` return 404. The start body is `{}`, so `databaseDirectory` is not forwarded.
- **E-3 (TD-04)** Scheduled runs dispatch and keep wave order, but carry no token at all: every
  platform call from a scheduled run returns 401. Scheduled execution is not operational until E-1
  is decided.

Fixable follow-ups F-1…F-5 are tasks T074–T078.

## Resolution by spec 004 (2026-09-23)

Spec [`004-backend-hardening`](../004-backend-hardening/spec.md) reduced the backend to what T070
proved:

- **E-1** (60 s token, no refresh) — addressed by 004: documented as a known limitation (README
  "Known limitations (v1)"), not fixed.
- **E-2** (5 of 7 step types 404) — addressed by 004: the support set is `integrity-check` only;
  the other 6 types (including `defragment-globals`, never proven) are `available: false` and
  refused on validate, dispatch, schedule and rerun with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`.
- **E-3** (scheduled runs carry no token) — addressed by 004: scheduling documented as
  non-operational; `/schedule` kept for contract continuity, no code change.
- **F-1** (WQM write endpoint) — fixed by 004: `PUT /api/admin/v2/wqm-category?name=`.
- **F-3** (unknown category only caught at enqueue) — fixed by 004: `CATEGORY_NOT_FOUND` at
  validation, against the platform's category list.
- **F-4** (built-in categories fail the invariant) — fixed by 004: `0` in `maxWorkers` /
  `maxTotalWorkers` means unbounded.
- **F-2**, **F-5** — unchanged, still open.

## E-1 fixed for manual dispatch (2026-09-25)

Found while building the live-run screen: `/api/admin/refresh` revokes the previous access
token, so a run dispatched with a client's own token died at that client's next refresh (~45 s),
earlier than the documented 60 s. Fix: dispatch accepts an optional `runCredential.refreshToken`
from a sign-in dedicated to the run; the run loop renews that pair itself (single renewer) and
`FinalizeRun` erases it. Runs longer than 60 s now complete (demo wave, 2 m 33 s). Without
`runCredential` nothing changes. **E-3** (scheduled runs) is still open: a scheduled run has no
sign-in to renew. Details: `specs/002-canvas-ui/tasks.md` §E-1.

Also fixed while there, with tests: a 4xx on a status check left the step `running` forever
(`PollInFlightSteps`), and a cancelled run finalized as `completed` (`FinalizeRun`).
Still open for the backend owner: the SSE response is gzipped by the web gateway and breaks
mid-stream in browsers (the canvas polls instead); the run log is never written; per the code,
rerun of a step in an already-terminal run is not picked up — `RerunStep` queues a new StepRun
but no loop is running any more (the canvas only offers *Re-run step* while the run is live).
