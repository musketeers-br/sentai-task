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

## R-8 — Run-credential owner *(to verify at the start of task 5)*

Question: does the `sub` returned by `/api/admin/refresh` name the owner of the **refresh token**
(the run sign-in), independently of the bearer used for the call? Spec 001 evidence 01/02 shows
`sub` in the flat login/refresh envelope, but only for one user. Verify with two users on the
container; if `sub` does not identify the refresh-token owner, FR-013 cannot be met as written:
stop and amend the spec before shipping (plan Risks).

