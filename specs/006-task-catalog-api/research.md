# Research — 006 Task Catalog API (Phase 0)

All spikes ran on the real target, container `sentai-task-iris-1` (IRIS for UNIX 2026.2 Build 221U,
namespace `IRISAPP`), on 2026-09-26 (instance clock), with the throwaway classes
`sentai.spike.R006` / `sentai.spike.R006Task`. Both were loaded into the container only and never
added to the repository. `R006Task` is a `%SYS.Task.Definition` whose `OnTask` returns OK, or
returns `$$$ERROR($$$GeneralError, "SpikeR006 deliberate failure")` when `Fail = 1`.

**Test operators**: these were temporary IRIS users. Their passwords were generated inside IRIS
(`GenCryptRand`), passed through a global and never printed or written to a file.

| User | Role | Resources |
|---|---|---|
| `spk6op` | `SentaiSpike6Op` | `%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW` (no task privilege) |
| `spk6adm` | `SentaiSpike6Adm` | the same plus `%Admin_Task:U` |

The platform's management API was called from inside the container (`%Net.HttpRequest` →
`localhost:52773`), which is the same path the product's `AdminApiClient` uses. Tokens were
obtained with `POST /api/admin/login` (Basic) as each test operator.

**Cleanup (verified, three runs)**: 134 `SpikeR006*` tasks and 280 history rows were deleted. Users, roles,
classes, `^sentaiSpike006` and `/tmp` files were removed. `spike tasks left: 0`, `spike history
left: 0`, `classes left: 00`, `users left: 00 roles left: 00`. No pre-existing task was modified.
Task 4 `Integrity Check` was already `Suspended=2` before the spike and still is (`task 4 Suspended
(untouched)=2`).

---

## R-1 — Source of the reads

### (a) Management API with the operator's credential

**Command**: as `spk6adm`, call `GET /api/admin/v2/tasks`, then `GET /api/admin/v2/task?id=` and
`GET /api/admin/v2/task/info?id=` for every listed id. As `spk6op`, make the same three calls.

**Output** (verbatim, task 4 = built-in Integrity Check):

```
R1a adm list code=200 tasks=19 elapsed=0.063s
list[4]={"Name":"Integrity Check","Type":"System","Namespace":"%SYS","Description":"Integrity check for databases at 2:00 am every Monday","Id":4,"Suspended":false,"LastFinished":"","NextScheduled":"2026-09-28 02:00:00"}
single[4] code=200 {…"result":{"Name":"Integrity Check","RunAsUser":"_SYSTEM",…,"TaskClass":"%SYS.Task.IntegrityCheck","NameSpace":"%SYS","TimePeriod":"Weekly",…}}
info[4] code=200 {…"result":{"Type":"System","Status":"1","Error":"","LastSchedule":"2026-09-25 21:23:00","LastStarted":"","LastFinished":"","NextScheduled":"2026-09-28 02:00:00","Suspended":true}}
info[7] {…"result":{"Type":"System","Status":"1","Error":"Success","LastSchedule":"2026-09-26 00:00:01","LastStarted":"2026-09-26 00:01:00","LastFinished":"2026-09-26 00:01:00","NextScheduled":"","Suspended":false}}
list[7] {"Name":"Purge Audit Database",…,"Id":7,"Suspended":false,"LastFinished":"2026-09-26 00:01:00","NextScheduled":"Runs After #1:00"}
R1a op list code=403 body={"status":{"errors":[],"summary":""},"console":[],"result":{}}
op single: 403 {"status":{"errors":[],"summary":""},"console":[],"result":{}}
op info: 403 {"status":{"errors":[],"summary":""},"console":[],"result":{}}
adm 404 single: 404 [{"status":{"errors":[{"error":"ERROR #5809: Object to Load not found, class '%SYS.Task', ID '99999'","code":5809,"domain":"%ObjectErrors","id":"LoadObjectNotFound","params":["%SYS.Task","99999"]}],"summary":"ERROR #5809: Object to Load not found, class &#39;%SYS.Task&#39;, ID &#39;99999&#39;"},"console":[],"result":{}}]
adm 404 info: 404 [same body]
```

**The list read is lossy**. Evidence from the same instance, as the container user:

```
%SYS.Task:TaskListFilter row 4 → … ID=4; Suspended=Suspend Reschedule; Last Finished=; Next Scheduled=2026-09-28 02:00;
%SYS.Task obj 4 → Suspended=2 DisplayNextScheduled=2026-09-28 02:00:00
```

- `Suspended`: the list query returns the display text (`Suspend Leave` / `Suspend Reschedule`),
  and the API turns it into a boolean that comes out `false`. **Every suspended task is listed as
  `Suspended:false`** (task 4 above, and temp task 1003 in R-3). The info read returns `true`.
- `NextScheduled`: the list truncates it to minutes and appends `":00"` (`2026-09-26 01:30:00`
  in the list vs. `2026-09-26 01:30:47` in info). For run-after tasks this produces
  `"Runs After #1:00"`. Info returns `""` for those tasks.
- The list carries neither class, run-as user, status nor error.

### (b) In-process, under the operator's identity

**Command**: a background job signs in as each operator (`$SYSTEM.Security.Login`) and runs the
SQL `SELECT … FROM %SYS.Task`, then `##class(%SYS.Task).%OpenId(4)`, then
`##class(%SYS.Task).Suspend(id,1)`.

```
spk6op  sql  who=1 | spk6op  | SentaiSpike6Op  -> ERROR #5540: SQLCODE: -99 Message: User spk6op is not privileged for the operation
spk6adm sql  who=1 | spk6adm | SentaiSpike6Adm -> ERROR #5540: SQLCODE: -99 Message: User spk6adm is not privileged for the operation
spk6op  open who=1 | spk6op  | SentaiSpike6Op  -> 1 |  | %SYS.Task.IntegrityCheck|_SYSTEM
spk6adm open who=1 | spk6adm | SentaiSpike6Adm -> 1 |  | %SYS.Task.IntegrityCheck|_SYSTEM
spk6op  suspend who=1 | spk6op | SentaiSpike6Op -> 1 |          ← suspended task 1003 (see R-3)
```

As the container user, the logical values are internal. `LastStarted` is `$H` (`67839,0`) and
`0` when never run, and `Suspended` is `0/1/2`, so a formatting layer of our own would be needed.

### Decision — (a) management API, with the operator's own token

| Criterion | (a) management API | (b) in-process |
|---|---|---|
| Fidelity | list + single + info carry every field the spec names, already formatted by the platform (`YYYY-MM-DD HH:MM:SS`) | SQL needs SQL privileges nobody has (`-99`); objects return internal formats we would have to reformat |
| Privilege | `%Admin_Task` required: 403 for `spk6op`, 200 for `spk6adm` | **no task privilege checked**: `spk6op` (no `%Admin_Task`) read every task and **suspended one** |
| Refusal | HTTP status + platform envelope | none: the operation succeeds |
| Cost, 151 tasks | 1 + 2N = 303 calls, 0.38 s (R-2) | 1 query |
| 60 s token (E-1) | the whole read takes < 0.5 s on one token | n/a |

We choose (b) nowhere. The object path lets an operator whom the management API refuses read and
change the Task Manager, which Constitution III forbids. The read-source rules are:

- **list** → which tasks exist (`Id`, `Name`, `Namespace`) and nothing else;
- **single** → `TaskClass`, `RunAsUser`, `TimePeriod`;
- **info** → `Status`, `Error`, `LastStarted`, `LastFinished`, `NextScheduled`, `Suspended`.

**Platform finding for the README**: on 2026.2, `%SYS.Task.Suspend` / `%OpenId` called in-process
do not check `%Admin_Task`. The history even records it: `"Result":"Suspended task", …
"Username":"spk6op"`. The product never takes that path.

**Not proven**: the source (`ResourcesOR`) suggests that reads accept `%Admin_Task` **or**
`%Admin_Operate`. Only "neither → 403" and "`%Admin_Task` → 200" were run.

## R-2 — Performance (SC-005)

**Command**: add 130 temp tasks (151 in total), then run the full sequential read (list + single +
info per task) as `spk6adm` three times.

```
R2 run 1 tasks=151 calls=303 elapsed=0.383s
R2 run 2 tasks=151 calls=303 elapsed=0.377s
R2 run 3 tasks=151 calls=303 elapsed=0.380s
non-200 per-task reads: 0
```

**Decision**: sequential, with no concurrency and no batching. That is about 5× below the 2 s
target for about 150 tasks, and one access token covers the whole read. The product-level timing
(through `/csp/sentai/api/v1`) is quickstart (e).

## R-3 — Suspend / resume (FR-006)

**Contract (proven)**: `POST /api/admin/v2/task/suspend?id=<id>` and
`POST /api/admin/v2/task/resume?id=<id>`, with `Content-Type: application/json` and **a JSON
body** (`{}`).

```
SUSPEND adm (no body):        415 {"status":{"errors":[{"error":"ERROR #40330: Expected the request content type to be application/json",…}]…}}
SUSPEND {}:                   200 {"status":{"errors":[],"summary":""},"console":[],"result":{}}
info  → "NextScheduled":"2026-09-27 03:00:00","Suspended":true          obj Suspended=1
list  → "Suspended":false                                               ← lossy list, R-1
SUSPEND {} again:             200 {…}        (idempotent)
RESUME {}:                    200 {…}
RESUME again (not suspended): 200 {…}        (idempotent)
info  → "Suspended":false
SUSPEND {"LeaveInQueue":false}: 200 → info Suspended:true, obj Suspended=2 ("Suspend Reschedule")
SUSPEND op {}:                403 {"status":{"errors":[],"summary":""},"console":[],"result":{}}
RESUME op:                    403 (same body); info afterwards unchanged ("Suspended":false)
SUSPEND missing {}:           404 {"status":{"errors":[{"error":"ERROR #5809: Object to Load not found, class '%SYS.Task', ID '99999'",…}]…}}
SUSPEND no id:                400 {…"ERROR #40300: Query parameter 'id' is required."…}
OLD product path POST /api/admin/v2/tasks/<id>/suspend: 404 (empty body)
```

**Decisions**:

- The product sends the platform default (`{}`, i.e. `LeaveInQueue` = 1, `Suspended=1`). It does
  not expose `LeaveInQueue` (YAGNI).
- **A suspended task keeps its `NextScheduled`** in info (`2026-09-27 03:00:00` above). The
  spec's "no longer shows a next run" is not what the platform does. We return the platform's
  value verbatim (FR-003). SC-004 is judged on `suspended` only (see plan, Spec deviations).
- The platform's `RunSuspend` source ignores the `%Status` of `Suspend()` and always answers 200
  when the task exists. A 200 therefore does not prove the effect. The product **re-reads info
  after the call** and reports the platform's post-state. If that state is not the requested one,
  the product answers `502 SUSPEND_NOT_APPLIED` with the info read verbatim.
- The fallback "not supported on target" error is not needed and is not built, because the
  contract is proven.

## R-4 — History (FR-008)

**Contract (proven)**: `GET /api/admin/v2/task/history?taskId=<id>` (the parameter is `taskId`,
not `id`). The response is descending, with `%Admin_Task` or `%Admin_Operate` per source, and 403
for `spk6op`.

```
hist b[0] {"LastStart":"2026-09-26 01:31:00","Completed":"2026-09-26 01:31:00","Status":"ERROR #5001: SpikeR006 deliberate failure","Result":"","TaskId":1004,"Namespace":"IRISAPP","Routine":"sentai.spike.R006Task","Pid":"8776","ErrDate":"2026-09-26","ErrNumber":1,"Name":"SpikeR006-B","Username":"spk6adm","LogDatetime":"2026-09-26 01:31:00"}
hist a[0] {"LastStart":"2026-09-26 01:31:00","Completed":"2026-09-26 01:31:00","Status":"1","Result":"Success",…,"Routine":"sentai.spike.R006Task",…,"Username":"spk6adm",…}
hist task1 first={"LastStart":"2026-09-26 00:00:00","Completed":"2026-09-26 00:00:00","Status":"1","Result":"Success","TaskId":1,"Namespace":"%SYS","Routine":"%SYS.Task.SwitchJournal",…}
hist a (admin events) {…"Status":"1","Result":"Suspended task",…,"Routine":"TASKMGR",…,"Username":"spk6op",…}
                      {…"Result":"Create SpikeR006-A",…,"Routine":"TASKMGR",…,"Username":"irisowner",…}
hist b op 403 {"status":{"errors":[],"summary":""},"console":[],"result":{}}
hist missing (taskId=99999) 200 {…"result":[]}
hist ?id= (wrong param) 200, 11977 bytes   ← parameter ignored, returns all history
```

**Findings**:

- History **mixes executions with administrative events**. Every observed execution row has
  `Routine` equal to the task's `TaskClass` (`%SYS.Task.SwitchJournal`, `sentai.spike.R006Task`).
  Every create/suspend/resume row has `Routine = "TASKMGR"`.
- `LastStart` and `Completed` have minute precision (the API pads them with `":00"`), so a
  duration computed from them would be invented precision.

**Decision (US-5 is included)**: `recentRuns` is the first 5 rows of that read whose `Routine`
equals the task's `class` from the single read. Each row is passed through with the platform's
own keys (`LastStart`, `Completed`, `Status`, `Result`, `Username`, `LogDatetime`), and no
duration is computed. `recentRuns` is returned only by the single-task read. It is `[]` when the
proven read has no execution rows, and it is absent if the history read itself fails (flagged in
`unavailable`).

## R-5 — Empty values and timestamps (passed through, never reformatted)

| Situation | Platform value (info unless noted) |
|---|---|
| Never ran | `LastStarted:""`, `LastFinished:""`, `Status:"1"`, `Error:""` |
| Last run OK | `Status:"1"`, `Error:"Success"` (task 7, temp task A) |
| Last run failed | `Status:"0 <serialized %Status, 199 chars>"`, `Error:""` (see below) |
| Run-after task | info `NextScheduled:""`; single `TimePeriod:"Run After"`; list `"Runs After #1:00"` (artefact) |
| Suspended | info `Suspended:true`, `NextScheduled` **kept** |
| Timestamps | `YYYY-MM-DD HH:MM:SS` (info, single), minute-padded in list and history |

**Failed-run status decoded (re-spike, same cleanup)**:

```
info.Status first2=[0 ] len=199 Error=[]
decoded=[ERROR #5001: SpikeR006 deliberate failure] isErr=1
sameAsObject=1 DisplayStatus=[ERROR #5001: SpikeR006 deliberate failure]
hist[0].Status=[ERROR #5001: SpikeR006 deliberate failure] Routine=sentai.spike.R006Task
```

**Decision**: the platform's `Status` is a serialized `%Status`. It survives the JSON round-trip
byte for byte (`sameAsObject=1`). `status` is therefore returned as the platform's **own text**
for it (`$SYSTEM.Status.GetErrorText`). That text equals the history row's `Status` and the
portal's `DisplayStatus`, so it is the platform's rendering and not ours. The OK value `"1"` is
passed through as `"1"`, and anything that is not a serialized error is passed through
unchanged. `lastError` is info `Error` **verbatim**, including `"Success"` after a successful run
and `""` after a failed one. The README states both facts.

## Other facts behind the design

- **Name generator (spec 003)**: `Dispatcher.CreateNativeTask` writes
  `"SentaiTask: "_flowId_"#"_stepId`. Here `flowId` is the `sentai.model.Flow` `%ID` (positive
  integer from the URL). `stepId` is `Step.id`, whose schema is `^[0-9A-Za-z_-]{1,8}$` (rendered
  `#01`, but the ids themselves are not guaranteed to be two digits). The live tasks 1000–1002 are
  `SentaiTask: 1#01..03`, class `sentai.dispatch.ScheduledFlowTask`.
- **Step-type catalog versus the instance**: classes of the 16 native tasks were checked with
  `%Dictionary.CompiledClass`.

  ```
  %SYS.Task.PurgeAuditDatabase=0 %SYS.Task.PurgeAudit=1 %SYS.Task.CompactGlobals=0 %SYS.Task.Defragment=0
  %SYS.Task.IntegrityCheck=1 %SYS.Task.SwitchJournal=1 %SYS.Task.PurgeTaskHistory=1
  7:Purge Audit Database:%SYS.Task.PurgeAudit      3:Purge Tasks:%SYS.Task.PurgeTaskHistory
  ```

  The catalog's `purge-audit-records` class (`%SYS.Task.PurgeAuditDatabase`) **does not exist**.
  The platform's audit purge task is `%SYS.Task.PurgeAudit`, which is what spec US-1 scenario 3
  needs. `compact-globals` and `defragment-globals` point at classes that do not exist either.
  These types are `available:false` today. Only the audit-purge entry matters for FR-004 (plan
  D-4).
- **Existing product defects confirmed**: `/catalog/tasks/{id}/suspend` calls a path that
  returns 404. `suspended` comes from the lossy list, so the `suspended` filter never matches.
  `ReadCatalogTask` re-lists everything to find one task.
- **Frontend**: `/catalog/tasks` has no consumer in `frontend/src` today (spec 007 will add
  one), so nothing breaks there.
