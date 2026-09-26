# Research — 005 Declared Custom Steps (Phase 0)

All spikes ran on the real target, container `sentai-task-iris-1` (IRIS 2026.2, namespace
`IRISAPP`), on 2026-09-25/26, with a throwaway class `sentai.spike.R005` loaded into the container
only (never in the repository). Cleanup afterwards: class deleted, spike globals killed in
`IRISAPP` and `%SYS`, test user and role deleted, `/tmp` file removed.

The "test operator" was a temporary IRIS user `sentaispike` with a single role `SentaiSpikeOp` =
`%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW` — enough to run the product's code, nothing else. Its
password was generated inside IRIS (`GenCryptRand`), handed to the spike process through a global
erased on first read, never printed or stored in a file.

---

## R-1 — Identity inside the worker *(gate of US-5, decides D-1)*

**Command**: a background process signs in as the test operator (`$SYSTEM.Security.Login`), then
runs the product-shaped chain twice — inline, and through `JOB` (the shape of `RunLoop`, which is
JOB'd from the REST request) — each creating `$SYSTEM.WorkMgr.%New(,,"Default")`, queueing an item
that records `$USERNAME, $ROLES, $NAMESPACE, IsWorkerJob()`, then `Sync()`.

**Output** (verbatim):

```
^sentaiSpike("op","login")=$lb(1,"sentaispike","SentaiSpikeOp")
^sentaiSpike("op","job")=$lb("sentaispike","SentaiSpikeOp","IRISAPP","6874")
^sentaiSpike("op","worker")=$lb("sentaispike","SentaiSpikeOp","IRISAPP",1,"6781")
^sentaiSpike("op-job","job")=$lb("sentaispike","SentaiSpikeOp","IRISAPP","6875")
^sentaiSpike("op-job","worker")=$lb("sentaispike","SentaiSpikeOp","IRISAPP",1,"6781")
```

Baseline as the container's own user: `worker=$lb("irisowner","%All","IRISAPP",1,"6781")` — the
**same worker process (6781)** took each queuer's identity per item.

**Decision — INHERITS.** A WorkMgr worker runs each item with the `$USERNAME`/`$ROLES` of the
process that queued it, including when the queuer is a `JOB` child. D-1 is proven: declared steps
run with the dispatching operator's own authority. Per Clarifications Q1 → A, **all** proven
declared types may be released (including the instance-changing ones of D-2).

**Caveat recorded**: `$SYSTEM.Security.Login` in a *terminal* session dropped the session with
`Access Denied` (the test user lacks `%Service_Terminal`) — a terminal-service check, not part of
the product path; the background run above is the faithful test.

**Alternatives considered**: none needed (no identity-assumption mechanism is required).

## R-5 — Native task classes in-process *(run because R-1 = inherits)*

Classes present on 2026.2: `%SYS.Task.SwitchJournal` (no parameters),
`%SYS.Task.PurgeTaskHistory` (property `KeepDays %Integer`), both `%Extends("%SYS.Task.Definition")`.

**Platform denies the unprivileged operator** (Constitution III working as intended):

```
^sentaiSpike("natop","switch")=$lb("exception","<PROTECT> 206 OnTask+1^%SYS.Task.SwitchJournal.1 /usr/irissys/mgr/", …,"sentaispike","IRISAPP")
^sentaiSpike("natop","purge") =$lb("exception","<PROTECT> 206 OnTask+1^%SYS.Task.PurgeTaskHistory.1 /usr/irissys/mgr/", …,"sentaispike","IRISAPP")
```

**Platform allows a privileged operator** — journal switched `.001 → .002 → .003`, purge OK:

```
("natadmin2","switch")=$lb("status","","/usr/irissys/mgr/journal/20260926.002","/usr/irissys/mgr/journal/20260926.003","irisowner","%SYS")
("natadmin2","purge") =$lb("status","", …,"irisowner","%SYS")
```

**Finding (design-critical)**: native `OnTask()` switches the process to namespace `%SYS` and does
**not** restore it — the spike's next global write landed in `^|"%SYS"|sentaiSpike`. The executor
MUST isolate the namespace (`New $NAMESPACE`) around the task call.

**Decisions**:
- `switch-journal` and `purge-task-history` move to the in-process executor; `available: true`
  once the quickstart (e) evidence is recorded. Privilege is the platform's call: an operator
  without it gets the `<PROTECT>` text verbatim as the step's failure reason.
- Namespace required: none from us — the class switches to `%SYS` itself; we only protect ours.
- Parameters: `purge-task-history.keepDays` → `KeepDays` (integer ≥ 0, default 30, required no).
- Reversibility: switch-journal is not reversible but harmless (a new journal file); purge is
  destructive and irreversible → stays `destructive: true` (typed confirmation, not schedulable).

## R-2 — Named WQM category

`$SYSTEM.WorkMgr.%New(, , category)` accepts a named category (used by the product since spec 003;
unknown category → error `#7823`, spec 003 evidence). Methods on 2026.2 (read from
`%Dictionary`): `Queue, QueueCallback, Detach(&token, timeout=86400), Attach(token), Pause,
Resume, StopWorkers, NumberWorkers, DefaultNumWorkers(category), IsWorkerJob, Free, Flush`.

**Decision**: declared steps are queued exactly like integrity checks — one WorkMgr group per
step on the step's effective category — so the category's ceilings govern both kinds alike.
**Not measured** in this timebox: saturation behaviour at the ceilings (no difference expected
since the mechanism is the same object); recorded as an assumption, not a proof.

## R-3 — Embedded Python inside a worker

```
("op","py")=$lb("/usr/irissys/mgr/journal/",
  "ok total=1081100128256 free=1013195870208 pctfree=93.7",   ← /usr/irissys/mgr/
  "ok total=1081100128256 free=1013195870208 pctfree=93.7",   ← journal dir
  "error FileNotFoundError: [Errno 2] No such file or directory: '/nonexistent/dir/'", 1)
```

**Decision**: `[ Language = python ]` runs inside the worker (`IsWorkerJob()=1`), under the test
operator too; `shutil.disk_usage` reads the instance's own directories; an unreadable path is a
Python exception, returned as text. The storage headroom check is implemented this way; the
journal directory comes from `%SYS.Journal.System.GetPrimaryDirectory()`.

## R-4 — Timeout without stopping the wave

```
detach returned at 5768.072393          ← queuer released immediately
("det","slow","start")=5768.07244
("det","slow","end")=$lb(5771.077657,"irisowner")   ← 3 s item finished after detach
```

**Decision**: for a declared step the run loop (1) transitions the StepRun to `running`, (2) queues
the item on a **new** WorkMgr group, (3) `Detach`es it and moves on — never `Sync()` (that would
block the loop for the whole task). The **worker** writes the terminal state. The loop enforces the
timeout: a `running` declared step older than its timeout (default 60 min when 0) is transitioned
to `failed` ("timed out after N min"). `IsLegalTransition` already refuses terminal → terminal, so
a late worker completion cannot overwrite the timeout (its transition returns an error, ignored).
The underlying work may keep running after the timeout — same limitation as F-2, documented.

**Also observed**: an error in one item makes `Sync()` return that error and the group's result
unreliable for the others → **one group per step** (as `StartStep` already does), never several
steps per group.

## R-6 — Declared class missing / not a task

```
R6 %SYS.Task.SwitchJournal compiled=1 isTask=1
R6 %SYS.Task.PurgeTaskHistory compiled=1 isTask=1
R6 sentai.spike.R005 compiled=1 isTask=0
R6 sentai.steps.DoesNotExist compiled=0 isTask=-
```

**Decision**: validation refuses a declared step with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` when its
catalog class is not compiled (`%Dictionary.CompiledClass.%ExistsId`) or does not extend
`%SYS.Task.Definition`. The class name read here is the **catalog's**, never the step's.

## R-7 — Unexpected error in the task

`Boom()` (1/0) surfaced as `ERROR #5002: ObjectScript error: <DIVIDE>Boom+1^…` from the group.
**Decision**: the worker wraps the task call in `Try/Catch`; an exception becomes `failed` with
`ex.DisplayString()` verbatim; a returned error `%Status` becomes `failed` with
`$SYSTEM.Status.GetErrorText(sc)` verbatim. The run loop never sees an exception (Constitution IV).

## Other decisions

- **Declaration mechanism**: extend the existing `XData Catalog` in `sentai.registry.StepType` —
  one closed, versioned block, one diff per new type. Entries gain `label`, `executor`
  (`platform-api` | `in-process`) and `parameters[]`. No second registry, no discovery by
  superclass (that would let any compiled class become a capability without touching the catalog).
- **Report result**: additive `StepRun.result` (JSON text, ≤ 8 KB) exposed as `result` in the run
  read; the flow document is untouched. Written only by the worker, from the task object's
  `Result` property if the class declares one (our shipped classes do; native ones don't).
- **Parameter schema scope**: enforced only for types that declare `parameters` (in-process
  types). `integrity-check` keeps today's behaviour (its steps carry `{}`), so no current flow
  changes validity.
- **Database sizes**: `db-size-report` and the headroom check list databases through the platform's
  own database query from within the worker (operator's authority); an operator who may not read
  it gets the platform's message verbatim. Exact query confirmed in the task that implements it.

## Review 2026-09-26 — code facts behind plan rev. 2

- **Event stream**: `StreamEvents` re-reads the Run every 0.5 s and emits when `eventVersion` grew;
  `StepRun.TransitionTo` bumps it with `UPDATE sentai_model.Run SET eventVersion = eventVersion + 1`
  in the writing process. Transitions written by a worker are streamed with no change.
- **Re-run path**: `RerunStep` only inserts a `queued` StepRun; the live `RunLoop` (the
  dispatcher's job) queues it → a re-run executes under the dispatcher's identity/credential,
  whoever asked. → plan ID-2.
- **Scheduled path**: `ScheduledFlowTask.OnTask` dispatches and starts the loop with no token; an
  in-process step there would run as the Task Manager's run-as user. → plan ID-3.
- **Dispatch credential**: `DispatchFlow` stores the request token plus the optional
  `runCredential.refreshToken`; nothing checks that both belong to the same user. → plan ID-1.
- **Transition guard**: `IsLegalTransition` refuses any move out of `completed`/`failed`/
  `cancelled`, but `TransitionTo` checks the **in-memory** state, so a stale object could still
  win → plan's `TransitionLocked` (exclusive open + fresh read).
- **Tests encoding "switch-journal unsupported"**: backend `StepTypeTest`,
  `StepAvailabilityRuleTest` (24 refusals incl. switch-journal and purge-task-history); e2e
  `us1-flow-composition` (palette list), `us2-inspector-validation` Q4 and `us4-live-run`
  ("2 errors … (#04, #05)"). No frontend **unit** test depends on `purge-task-history`
  pausable/availability (their catalogs are local fixtures).

## R-9 — Database sizes from `IRISAPP` *(spec 005 T005, 2026-09-26)*

**Command** (container, namespace `IRISAPP`, as the container's own user): the class query
`%SYS.DatabaseQuery:FreeSpace` — formal spec `Mask:%String="*"`, `ROWSPEC` =
`DatabaseName, Directory, MaxSize, Size, ExpansionSize, Available, Free (% Free), DiskFreeSpace,
Status, SizeInt, AvailableNum, DiskFreeSpaceNum, ReadOnly` — run through
`%SQL.Statement.%PrepareClassQuery("%SYS.DatabaseQuery", "FreeSpace")` and `%Execute()`.

**Output** (first rows, verbatim values):

```
IRISAPP_DATA   /data/IRISAPP_DATA/              Size=11MB  SizeInt=11  AvailableNum=1.5  Free=14 Status=Mounted/RW
IRISSYS        /usr/irissys/mgr/                Size=159MB SizeInt=159 AvailableNum=6.5  Free=4  Status=Mounted/RW
IRISAPP_CODE   /usr/irissys/mgr/IRISAPP_CODE/   Size=11MB  SizeInt=11  AvailableNum=5.9  Free=54 Status=Mounted/RW
ENSLIB         /usr/irissys/mgr/enslib/         Size=153MB SizeInt=153 AvailableNum=11   Free=7  Status=Mounted/R
…  (IRISAUDIT, IRISLIB, IRISLOCALDATA, IRISMETRICS, IRISSECURITY, IRISTEMP, …)
```

**Decision**: `db-size-report` and the storage headroom check list databases with this query,
from the worker, under the operator's authority. `sizeMB` = `SizeInt`, `freeMB` = `AvailableNum`
(free space **inside** the database file, MB); `directory` = `Directory`. The headroom check uses
the `Directory` values as its locations (plus the primary journal directory). A query error is
returned as the step's `%Status`, verbatim.

## R-8 — Run-credential owner *(verified 2026-09-26, spec 005 T011)*

Question: does the `sub` returned by `/api/admin/refresh` name the owner of the **refresh token**
(the run sign-in), independently of the bearer used for the call?

**Command** (container, from inside IRIS through the local web server): two temporary users A
(`sentai005a`) and B (`sentai005b`), passwords generated inside IRIS and never printed, both
deleted afterwards. Each signs in with `POST /api/admin/login`. Then `POST /api/admin/refresh`
with **bearer = A's access token** and **body = B's refresh token**; and, as a control, with A's
own pair.

**Output**:

```
loginA  200 sub=sentai005a
loginB  200 sub=sentai005b
crossed 200 sub=sentai005b   keys=access_token,refresh_token,sub,iat,exp
same    200 sub=sentai005a
```

**Decision**: `sub` names the owner of the refresh token, whoever the bearer is — FR-013 is met as
written. `/dispatch` redeems `runCredential.refreshToken` once before creating the run and
refuses with 403 `RUN_CREDENTIAL_USER_MISMATCH` when `sub` ≠ the requesting user
(case-insensitive); otherwise the fresh pair becomes the run credential. Note: the platform
accepts a refresh token under another user's bearer, which is exactly why the product must
compare `sub` itself.

## R-10 — Native types over REST, administrator and "unprivileged" operator *(spec 005 T013, 2026-09-26)*

Evidence: [evidence/e-native-types.json](evidence/e-native-types.json) (status + body only). For
this run only, `switch-journal` and `purge-task-history` were `available: true` on the dev
container; `purge-task-history` was reverted right after (held until spec 007 T009, see T016).

**Administrator** (temporary user, `%All`) — quickstart (e)1–3 as expected: schedule 422
(`DESTRUCTIVE_NOT_SCHEDULABLE` 02; `IN_PROCESS_NOT_SCHEDULABLE` 02, 03); dispatch without
confirmation 428 naming 02, with it 202; run `completed`; journal
`20260926.003 → 20260926.004`; 02 and 03 `executedAs = sentai005adm`.

**Operator without administrative privilege** — quickstart (e)4. The R-1 role
(`%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW`) plus SQL on schema `sentai_model` cannot pass
validation: the platform refuses its WQM category read (403), so every step reports
`CATEGORY_NOT_FOUND` (fail closed, spec 004 FR-006). The least addition that lets that read
succeed, found by trial on the container, is `%Admin_Manage:U` + `%DB_IRISSYS:R`
(`%Admin_Manage:U` alone → 500 `<PROTECT>` on `^oddCOM("Config.WorkQueues",…)`;
`%Admin_Operate:U` → 403). With that role (IRISSYS still read-only):

```
02 purge-task-history  completed  executedAs=sentai005op
03 switch-journal      failed     executedAs=sentai005op
   "ERROR #1142: Error switching journal file: ERROR #921: Operation requires %Admin_Operate:USE privilege"
journal unchanged (20260926.004 → 20260926.004)
```

**Finding — differs from quickstart (e)4's expectation** ("02 and 03 failed, each with
`<PROTECT>`"). What the spec needs is proven: each in-process step ran as the dispatching
operator (`executedAs`), the platform decided, and its refusal reached the operator verbatim
(Constitution III). But the platform's answer is not the one the quickstart predicted: with the
resources an operator needs to *validate* a flow, the platform **allows** the task-history purge,
and refuses the journal switch with `#921 … %Admin_Operate:USE`, not `<PROTECT>`. R-5's
`<PROTECT>` results were for the smaller R-1 role, which cannot get through validation over
REST. README states the privilege each native type needs as the platform reports it.
