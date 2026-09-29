# Implementation Plan: Scheduled Runs That Execute

**Branch**: `feat/spec015` (feature dir `015-scheduled-runs`) | **Date**: 2026-09-28 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (6 clarifications, 18 FRs, 6 SCs). Backend: a schedule service that
verifies passwords, stores them in the IRIS Wallet through the management API, and manages one
native task per flow with real timing; a rewritten `ScheduledFlowTask.OnTask` that reads the
secret through the platform, signs in and dispatches like *Run now*; a `trigger` on runs; a
constitution amendment. Frontend: a new *Schedule* dialog and the *Scheduled* marker in the
history. API: `POST /flows/{id}/schedule` changes shape, and `GET` and `DELETE` are added
([contracts/api-delta.md](contracts/api-delta.md)).

## Summary

1. **Proof first (T001).** Everything depends on four platform facts ([research R-1…R-4](research.md)):
   (a) the management API creates and deletes wallet collections and secrets with the operator's
   token; (b) a task process running as the run-as account can use the secret, and the platform
   refuses an account without the collection's use resource; (c) whether `%Wallet.KeyValue`
   `ApplyHTTP` can put the credential on the sign-in request **without the product reading the
   value** (preferred), or else `GetSecretValue` inside the task process is the fallback; (d) the
   Task Manager timing fields for the four schedule kinds, and the next-run time the platform
   reports for each.
2. **Schedule service (US1, US2).** `sentai.schedule.ScheduleService` (application) with
   `Schedule(flowId, request, operatorToken)`, `Read(flowId, operatorToken)` and
   `Unschedule(flowId, operatorToken)`. Order for `Schedule`: validate for schedule → verify each
   password with `AdminApiClient.Login` (primary and targets) → write the new secrets under new
   names (generation `g+1`) → create the new task → delete the previous task(s) and secrets
   (generation `g`, and legacy per-step tasks) → save the `Schedule` row. On any failure, it undoes
   only what it created in this call (FR-006). Each platform call uses the operator's token, and
   each refusal is returned verbatim.
3. **Firing (US1, US3).** `ScheduledFlowTask.OnTask` (runs as the run-as account in IRISAPP):
   `ScheduledStart.Fire(flowId)` → for the primary and each target, obtain a token pair by signing
   in with the stored credential (R-3) → `WaveDispatcher.Dispatch(flowId, [], runAs, token,
   targetTokens, trigger="scheduled")` → `StoreRunCredential` / `StoreTargetCredentials` →
   `StartBackgroundLoop`. If a step fails before the dispatch, `ScheduledStart` records a *start
   failure* run (failed, scheduled, no step runs, one log entry with the reason verbatim) and
   `OnTask` returns an error `%Status` with the same text, so the platform's task history shows it
   (FR-010).
4. **Timing (FR-001, FR-004, SC-005).** `sentai.schedule.Timing` maps the structured schedule to
   the Task Manager fields and renders it in words ([data-model §2](data-model.md)). The next run
   is read back from the platform (`task/info`), never computed by the product.
5. **Run trigger (FR-009, FR-016).** `Run.trigger` (`manual` default, `scheduled`). It is returned
   in run summaries and details, and filterable in `GET /runs?trigger=`. The spec 012 *Runs* screen
   gains a marker and a filter.
6. **Canvas (US4).** `ScheduleDialog.svelte` rewritten over a pure `schedule.ts` (picker state ↔
   request, words, field errors). It reuses spec 009's per-target password fields.
7. **Constitution (FR-018).** Amendment 1.1.0 (MINOR: Principle III materially expanded): "An
   application MAY keep an authentication secret only in the platform's own secret store, under a
   platform resource, so that each use is authorized by the platform; it MUST NOT keep one in its
   own storage." It comes with a Sync Impact Report and the template notes.

## Technical Context

**Language/Version**: ObjectScript (IRIS 2026.2); TypeScript 5.9 + Svelte 5.

**Primary Dependencies**: none new. Platform features: IRIS Wallet (`%Wallet.*`, management API
`/api/admin/v2/wallet/*`), Task Manager (management API `/api/admin/v2/task*`), `/api/admin/login`.

**Storage**:
- New persistent class `sentai.model.Schedule` (flow, kind, days, dayOfMonth, everyHours,
  startTime, runAs, taskId, generation, createdBy, createdAt). It holds no secret.
- `Run.trigger` (new property, default `manual`).
- Wallet collection `SentaiTask` (created by the installer, with `UseResource` and
  `EditResource` = the new resource `SentaiSchedule`). Secrets are named
  `flow-<id>-g<generation>-<instance>`, where `<instance>` is `primary` or a target name.
- `Flow.scheduleSpec` keeps the schedule in words (for the flow list and backward reading).

**Testing**:
- `%UnitTest`: `TimingTest` (four kinds → fields, words, invalid input), `ScheduleServiceTest`
  (order, rollback at each failing call, replace, legacy cleanup, unschedule, refusals verbatim;
  under `AdminApiDouble` with scripted wallet and task answers), `ScheduledStartTest` (fire
  success; secret unreadable; login refused; validation failed → start-failure run + error status;
  trigger and first log entry), `SecretHygieneTest` (SC-002 scan of `^sentai*`,
  `^IRIS.Temp.sentai*`, the product's tables and log after a full cycle).
- A real-platform acceptance script `scripts/schedule-evidence/acceptance.py` for SC-001, SC-003,
  SC-004 and SC-005 (it fires real tasks, so it takes minutes, like spec 008's quickstart).
- vitest: `schedule.test.ts`. Playwright: `us28-schedule.spec.ts` (dialog, schedule and unschedule
  against the real platform, no firing) plus one opt-in `@slow` firing test.

**Target Platform / Project Type**: as today.

**Performance Goals**: the firing adds one sign-in per instance (< 1 s locally); the schedule call
adds 1 + T verifications, S secret writes, 1 task create, 1 task read and the deletes (under 3 s
locally).

**Constraints**: no password outside the wallet (FR-003); the password travels only in the
schedule request body and the platform calls, never in logs (`AdminApiClient` must not log bodies;
checked in T001); all refusals verbatim; UI English.

**Scale/Scope**: ~6 new/changed backend classes, ~5 test classes, 1 dialog, 1 pure module,
contract delta, constitution amendment, docs.

## Constitution Check

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | `ScheduleService`/`ScheduledStart` (application) depend on `AdminApiClient` (infrastructure) and the model. The REST handler and the task class are edges that only delegate. `Timing` is pure. | ✅ |
| **II Closed Capability Set** | No code from input. The schedule is validated structured data (enums and ranges). The task class is fixed (`sentai.dispatch.ScheduledFlowTask`). | ✅ |
| **III Delegated Authorization** | Every write (task, secret) is made through the management API with the operator's token. Every read of the secret at firing is authorized by the platform against the collection's resource and the run-as account. Every step call is authorized with the run-as account's own token. Nothing about permissions is stored. Storing a *credential* is new; it is made explicit by amendment 1.1.0 (FR-018), confined to the platform's secret store. | ✅ with amendment |
| **IV Errors as Values** | Service methods return outcome values `{httpStatus, body|problem}` as `NativeScheduler` does; start failures become a recorded failed run, never a silent task. | ✅ |
| **V Verifiable Increments** | Increments: (1) schedule + fire a local flow end to end; (2) replace/unschedule without residue; (3) start failures visible; (4) targets and report steps scheduled; (5) canvas dialog; (6) history marker. Each with its failing test first. | ✅ |
| **VI Technology Agnosticism** | The amendment wording is technology-free ("the platform's own secret store"). | ✅ |
| SOLID / SoC | Timing, secrets, tasks and firing are separate units; `NativeScheduler` is retired into `ScheduleService`'s task calls. | ✅ |
| TDD / YAGNI | Failing tests first; no overlap control, no calendars. | ✅ |

**Governance**: this plan changes how scheduled runs authenticate, so the constitution review is
mandatory. The review concluded that a MINOR amendment is needed, to be merged in the same change
(T003).

## Decisions

- **D-1 Order of `Schedule` and rollback.** Verify → write new-generation secrets → create task →
  read its id and next run → delete the old task(s) and old-generation secrets → save the
  `Schedule` row. A failure before "delete old" removes the new secrets and the new task (best
  effort, with the operator's token), and the previous schedule keeps working (FR-006). A failure
  while deleting old items is reported as a warning in the answer (`residue: […]`), because the new
  schedule is already in place.
- **D-2 Verification.** `AdminApiClient.Login(baseUrl, runAs, password)` for the primary
  (loopback base URL) and each target (its registered address). The token pairs obtained are
  discarded immediately (not stored). A 401 is returned as 422 `CREDENTIAL_REFUSED` with the
  instance name and the platform's text.
- **D-3 Using the secret at firing.** Preferred: `%Wallet.KeyValue.ApplyHTTP(request)` puts the
  credential on the `%Net.HttpRequest` for `/api/admin/login`, so the product never reads the
  password into a variable ([R-3](research.md)). Fallback, if T001 shows `ApplyHTTP` does not fit a
  Basic sign-in: `%Wallet.KeyValue.GetSecretValue(name)` inside `ScheduledStart`, with the value
  held in a local variable that is killed right after the request is built, and never logged.
  T001 decides and records the choice here.
- **D-4 Task timing.** One task per flow: `Name = "SentaiTask: <flowId> <flow name>"` (spec 006's
  `TaskOrigin` is updated to read this form as well as the legacy `SentaiTask: <flowId>#<step>`),
  `TaskClass = sentai.dispatch.ScheduledFlowTask`, `RunAsUser = runAs`,
  `Settings = {FlowId}`, and timing fields per data-model §2. `IsRoot`/`StepId` are removed from
  the task class; legacy tasks that still carry them are ignored at firing, and only the new task
  starts runs. Legacy tasks are deleted on the next schedule or unschedule of their flow.
- **D-5 Start failure run.** `sentai.model.Run` with `state = failed`, `trigger = scheduled`,
  `dispatchedBy = runAs`, `startedAt = finishedAt = now`, no step runs, and one log entry (spec
  012 narrator: `Scheduled run could not start: <reason>`). The history shows it with 0 steps.
- **D-6 In-process steps become schedulable.** The run loop is started from the task process
  (running as the run-as account); in-process workers take that identity (spec 005 R-1). So
  `IN_PROCESS_NOT_SCHEDULABLE` is removed from `ValidateForSchedule`. `DESTRUCTIVE_NOT_SCHEDULABLE`
  stays.
- **D-7 Canvas dialog.** `schedule.ts`: `ScheduleForm` state, `toRequest(form)`,
  `describe(schedule)` ("Daily at 03:00", "Weekly on Mon, Thu at 22:30", "Monthly on day 1 at
  04:00", "Every 4 hours from 00:00"), `fieldErrors(form)`. The dialog shows the current schedule
  (from `GET …/schedule`), the picker, run-as, the password fields (primary plus
  `targetsUsed(flow)` from spec 009), the wallet sentence, the instance's current time (`instanceTime`), and the buttons *Schedule* /
  *Update*, *Renew credential*, *Unschedule* (with a confirmation). *Renew credential* posts the
  current timing with the new passwords: the same `Schedule` path, which gives a new generation
  (and a new task id) with the timing unchanged (spec US2-3). Passwords live only in the dialog's local
  state and are cleared on close.
- **D-8 Next run in the flow list.** `ListFlows` keeps returning `nextRun`, now from the
  `Schedule` row's last known platform value, refreshed whenever `GET …/schedule` or a schedule
  change reads the platform. This avoids one platform call per listed flow. The dialog always shows
  the live value. Documented as "as of the last read" in limitations.

## Increments

| # | Scope | First failing test | Then |
|---|---|---|---|
| 0 | Proof | T001 evidence | research decisions R-1…R-4 recorded |
| 1 | Schedule + fire, local steps | `TimingTest`, `ScheduleServiceTest` (happy path), `ScheduledStartTest` (success), acceptance SC-001 local | service, task class, timing, trigger, installer (collection + resource) |
| 2 | Replace / unschedule / legacy | `ScheduleServiceTest` (replace, rollback, legacy), acceptance SC-003 | service paths, `DELETE` route |
| 3 | Start failures | `ScheduledStartTest` (failures), acceptance SC-004 | start-failure run, task error |
| 4 | Targets and report steps | `ScheduledStartTest` (targets), acceptance SC-001 remote | target secrets, validator change |
| 5 | Canvas dialog | `schedule.test.ts`, `us28` | dialog |
| 6 | History marker | `RunListTest` (trigger filter), `us28` history case | `trigger` in list, marker and filter |
| 7 | Governance and docs | — | amendment, README, limitations, SC-002 scan |

## Project Structure

```text
specs/015-scheduled-runs/
├── plan.md  research.md  data-model.md  quickstart.md  analysis.md  tasks.md
├── contracts/api-delta.md
└── checklists/requirements.md

src/sentai/schedule/ScheduleService.cls     # new
src/sentai/schedule/Timing.cls              # new
src/sentai/schedule/ScheduledStart.cls      # new
src/sentai/model/Schedule.cls               # new
src/sentai/model/Run.cls                    # trigger
src/sentai/dispatch/ScheduledFlowTask.cls   # rewritten OnTask
src/sentai/dispatch/NativeScheduler.cls     # removed (logic moves to ScheduleService)
src/sentai/dispatch/WaveDispatcher.cls      # Dispatch(…, trigger)
src/sentai/validation/FlowValidator.cls     # ValidateForSchedule: in-process allowed
src/sentai/catalog/TaskOrigin.cls           # new task name form
src/sentai/rest/Dispatcher.cls              # GET/POST/DELETE /flows/{id}/schedule; trigger in runs
iris.script / module.xml                    # SentaiSchedule resource, SentaiTask wallet collection
tests/sentai/unittest/TimingTest.cls, ScheduleServiceTest.cls, ScheduledStartTest.cls, SecretHygieneTest.cls
scripts/schedule-evidence/acceptance.py     # new
frontend/src/lib/shell/schedule.ts (+ test) # new
frontend/src/lib/shell/ScheduleDialog.svelte
frontend/src/lib/runs/*                     # trigger marker and filter (spec 012 screen)
frontend/tests/us28-schedule.spec.ts        # new (us3-schedule.spec.ts updated)
.specify/memory/constitution.md             # 1.1.0
README.md, docs/limitations.md
```

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Storing a credential (amendment 1.1.0) | A run with nobody signed in must authenticate to the platform. | In-process execution as the task's run-as account (option B of clarification Q1) cannot run management-API steps, remote steps or report steps. Those are the product's core and its DPI-I-588 story. |
