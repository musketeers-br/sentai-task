/// Spec 015 (plan D-1, D-2, D-4): schedule, read and unschedule a flow. One native task per flow,
/// running as the run-as account, created and deleted through the platform's management API with
/// the operator's token (the platform decides; its refusal is returned verbatim). The run-as
/// passwords are verified by signing in, then kept only in the IRIS Wallet (sentai.schedule.Wallet).
/// Every method returns an outcome value {httpStatus, body} or {httpStatus, problem}.
Class sentai.schedule.ScheduleService Extends %RegisteredObject
{

Parameter NAMEPREFIX = "SentaiTask: ";

/// POST /flows/{id}/schedule (contracts/api-delta.md).
ClassMethod Schedule(flowId As %String, payload As %DynamicObject, token As %String, operator As %String) As %DynamicObject
{
    Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 0)
    Quit:'$IsObject(flow) ..Problem(404, "Flow '"_flowId_"' does not exist")
    If '$IsObject(payload) || ('payload.%IsDefined("schedule") && payload.%IsDefined("scheduleSpec")) {
        Quit ..Problem(400, "SCHEDULE_FORMAT: send {""schedule"": {""kind"", ""startTime"", …}, ""runAs"", ""password"", ""targetPasswords"": [{""target"", ""password""}]}")
    }
    Set errors = ##class(sentai.schedule.Timing).Validate(payload.schedule)
    If errors.%Size() {
        Set first = errors.%Get(0)
        Set out = ..Problem(400, "SCHEDULE_INVALID: "_first.detail)
        Do out.problem.%Set("code", "SCHEDULE_INVALID"), out.problem.%Set("field", first.field), out.problem.%Set("errors", errors)
        Quit out
    }
    Set runAs = payload.runAs, password = payload.password
    If (runAs = "") || (password = "") Quit ..Problem(400, "SCHEDULE_INVALID: runAs and password are required")

    // FR-007: destructive steps stay unschedulable; the rest of validation applies as for dispatch.
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(flowId, token)
    If '##class(sentai.validation.FlowValidator).HasNoErrors(report) Quit {"httpStatus": 422, "body": (report)}

    // One password per target the flow uses, no more, no less.
    Set targets = ..TargetsOf(flowId), given = ..TargetPasswords(payload.targetPasswords)
    If ($LTS(targets) '= $LTS(..Names(given))) {
        Set out = ..Problem(400, "TARGET_PASSWORDS_MISMATCH: the flow uses targets ["_$LTS(targets, ", ")_"]; passwords were given for ["_$LTS(..Names(given), ", ")_"]")
        Do out.problem.%Set("code", "TARGET_PASSWORDS_MISMATCH")
        Quit out
    }

    // D-2: every password is checked by signing in where it will be used; nothing is kept yet.
    Set refused = ..Verify("", "primary", runAs, password)
    Quit:$IsObject(refused) refused
    For i = 1:1:$LL(targets) {
        Set name = $LG(targets, i)
        Set target = ##class(sentai.model.Target).NameIndexOpen(name, 0)
        If '$IsObject(target) Quit
        Set refused = ..Verify(target.baseUrl, name, runAs, given.%Get(name))
        Quit:$IsObject(refused)
    }
    Quit:$IsObject(refused) refused

    // D-1: new-generation secrets, then the task, then remove the previous ones.
    Set existing = ##class(sentai.model.Schedule).ForFlow(flowId)
    Set oldGeneration = $S($IsObject(existing):existing.generation, 1:0), oldTargets = $S($IsObject(existing):existing.targets, 1:"")
    Set generation = oldGeneration + 1, written = ""
    Set sc = ##class(sentai.schedule.Wallet).Put(##class(sentai.schedule.Wallet).SecretName(flowId, generation, "primary"), runAs, password)
    Set:$$$ISOK(sc) written = written_$LB("primary")
    For i = 1:1:$LL(targets) {
        Quit:$$$ISERR(sc)
        Set name = $LG(targets, i)
        Set sc = ##class(sentai.schedule.Wallet).Put(##class(sentai.schedule.Wallet).SecretName(flowId, generation, name), runAs, given.%Get(name))
        Set:$$$ISOK(sc) written = written_$LB(name)
    }
    Set given = "", password = ""
    If $$$ISERR(sc) {
        Do ..DeleteSecrets(flowId, generation, written)
        Set out = ..Problem(403, "WALLET_REFUSED: "_$SYSTEM.Status.GetErrorText(sc))
        Do out.problem.%Set("code", "WALLET_REFUSED")
        Quit out
    }

    Set taskName = ..TaskName(flowId, flow.name)
    Set call = ##class(sentai.catalog.TaskService).PlatformPost("/api/admin/v2/task", ..TaskBody(flowId, taskName, runAs, payload.schedule), token)
    If (call.httpStatus < 200) || (call.httpStatus >= 300) {
        Do ..DeleteSecrets(flowId, generation, written)
        Quit ##class(sentai.catalog.TaskService).Refusal(call)
    }
    Set list = ##class(sentai.catalog.TaskService).PlatformRead("/api/admin/v2/tasks", token)
    Set taskId = $S((list.httpStatus = 200) && $IsObject(list.result):..NewestIdNamed(list.result, taskName), 1:"")
    If (taskId = "") {
        Do ..DeleteSecrets(flowId, generation, written)
        Quit ..Problem(502, "SCHEDULE_NOT_CONFIRMED: the platform accepted the create but lists no task named '"_taskName_"'")
    }

    // The previous schedule's tasks (and any legacy one-task-per-step task) and secrets go now.
    Set residue = []
    Do ..DeleteTasks(flowId, $S(list.httpStatus = 200:list.result, 1:[]), token, taskId, .removed, residue)
    Do:(oldGeneration > 0) ..DeleteSecrets(flowId, oldGeneration, $LB("primary")_$LFS(oldTargets), residue)

    Set nextRun = ..NextRun(taskId, token)
    Set:'$IsObject(existing) existing = ##class(sentai.model.Schedule).%New()
    Do existing.flowSetObjectId(flowId)
    Set existing.kind = payload.schedule.kind, existing.startTime = payload.schedule.startTime
    Set existing.days = $S(payload.schedule.kind = "weekly":..JoinArray(payload.schedule.days), 1:"")
    Set existing.dayOfMonth = $S(payload.schedule.kind = "monthly":+payload.schedule.dayOfMonth, 1:"")
    Set existing.everyHours = $S(payload.schedule.kind = "hourly":+payload.schedule.everyHours, 1:"")
    Set existing.runAs = runAs, existing.targets = $LTS(targets, ","), existing.taskId = taskId, existing.generation = generation
    Set existing.nextRun = nextRun, existing.updatedAt = $ZDATETIME($HOROLOG, 3)
    Set:(existing.createdAt = "") existing.createdAt = existing.updatedAt, existing.createdBy = operator
    Set sc = existing.%Save()
    Quit:$$$ISERR(sc) ..Problem(500, $SYSTEM.Status.GetErrorText(sc))
    Set describe = ##class(sentai.schedule.Timing).Describe(payload.schedule)
    Set f = ##class(sentai.model.Flow).%OpenId(flowId, 4)
    Set f.scheduleSpec = describe
    Do f.%Save()

    Set body = {"taskId": (+taskId), "nextRun": (nextRun), "describe": (describe), "residue": (residue)}
    Quit {"httpStatus": 201, "body": (body)}
}

/// GET /flows/{id}/schedule: the schedule with the platform's live next run, and the last
/// scheduled run.
ClassMethod Read(flowId As %String, token As %String) As %DynamicObject
{
    Set now = $ZDATETIME($HOROLOG, 3)
    Set s = ##class(sentai.model.Schedule).FlowIndexOpen(flowId, 0)
    If '$IsObject(s) {
        Set body = {"instanceTime": (now)}
        Do body.%Set("scheduled", 0, "boolean")
        Quit {"httpStatus": 200, "body": (body)}
    }
    Set nextRun = ..NextRun(s.taskId, token)
    If (nextRun '= "") && (nextRun '= s.nextRun) {
        Set w = ##class(sentai.model.Schedule).%OpenId(s.%Id(), 4)
        Set w.nextRun = nextRun
        Do w.%Save()
    }
    Set last = "", flow = flowId
    &sql(SELECT TOP 1 guid, state, startedAt INTO :guid, :state, :startedAt FROM sentai_model.Run WHERE flow = :flow AND "trigger" = 'scheduled' ORDER BY ID DESC)
    Set:(SQLCODE = 0) last = {"guid": (guid), "state": (state), "startedAt": (startedAt)}
    Set targets = []
    For i = 1:1:$L(s.targets, ",") { Do:($P(s.targets, ",", i) '= "") targets.%Push($P(s.targets, ",", i)) }
    Set body = {"schedule": (s.ToSchedule()), "describe": (##class(sentai.schedule.Timing).Describe(s.ToSchedule())),
                "runAs": (s.runAs), "targets": (targets), "taskId": (s.taskId), "nextRun": ($S(nextRun '= "":nextRun, 1:s.nextRun)),
                "lastRun": ($S($IsObject(last):last, 1:$$$NULLOREF)), "instanceTime": (now)}
    Do body.%Set("scheduled", 1, "boolean")
    Quit {"httpStatus": 200, "body": (body)}
}

/// DELETE /flows/{id}/schedule: removes every task of the flow (current and legacy) and every
/// secret of its schedule. Idempotent.
ClassMethod Unschedule(flowId As %String, token As %String) As %DynamicObject
{
    Set residue = [], removedSecrets = 0
    Set list = ##class(sentai.catalog.TaskService).PlatformRead("/api/admin/v2/tasks", token)
    If (list.httpStatus '= 200) || '$IsObject(list.result) Quit ##class(sentai.catalog.TaskService).Refusal(list)
    Do ..DeleteTasks(flowId, list.result, token, "", .removed, residue)
    Set s = ##class(sentai.model.Schedule).FlowIndexOpen(flowId, 4)
    If $IsObject(s) {
        Set instances = $LB("primary")_$LFS(s.targets)
        Do ..DeleteSecrets(flowId, s.generation, instances, residue)
        For i = 1:1:$LL(instances) { Set:($LG(instances, i) '= "") removedSecrets = removedSecrets + 1 }
        Do ##class(sentai.model.Schedule).%DeleteId(s.%Id())
    }
    Set f = ##class(sentai.model.Flow).%OpenId(flowId, 4)
    If $IsObject(f) && (f.scheduleSpec '= "") {
        Set f.scheduleSpec = ""
        Do f.%Save()
    }
    Set tasks = []
    For i = 1:1:$LL($G(removed)) { Do tasks.%Push(+$LG(removed, i)) }
    Quit {"httpStatus": 200, "body": {"removedTasks": (tasks), "removedSecrets": (removedSecrets), "residue": (residue)}}
}

/// --- helpers ---
ClassMethod TaskName(flowId As %String, flowName As %String) As %String
{
    Quit ..#NAMEPREFIX_flowId_" "_$E(flowName, 1, 80)
}

/// A task of `flowId` by name: this form ("SentaiTask: <id> <name>") or the legacy per-step form
/// ("SentaiTask: <id>#<step>").
ClassMethod IsTaskOf(name As %String, flowId As %String) As %Boolean
{
    Set head = ..#NAMEPREFIX_flowId
    Quit ($E(name, 1, $L(head) + 1) = (head_" ")) || ($E(name, 1, $L(head) + 1) = (head_"#"))
}

/// The create body (the fields the platform's schema requires, spec 006 R-1) with this
/// schedule's timing, running as `runAs`, starting today — or tomorrow when today's start time has
/// passed: the platform refuses a start in the past (ERROR #7432, e2e us28 finding).
ClassMethod TaskBody(flowId As %String, taskName As %String, runAs As %String, schedule As %DynamicObject) As %DynamicObject
{
    Set body = {
        "Name": (taskName), "RunAsUser": (runAs), "Description": "SentaiTask scheduled flow (spec 015)",
        "TaskClass": "sentai.dispatch.ScheduledFlowTask", "NameSpace": ($NAMESPACE),
        "EmailOnCompletion": [], "EmailOnError": [], "EmailOnExpiration": [],
        "ExpiresDays": "", "ExpiresHours": "", "ExpiresMinutes": "",
        "OutputDirectory": "", "OutputFilename": "", "Priority": "Normal",
        "StartDate": (..StartDate(schedule.startTime)), "EndDate": "", "RunAfterGUID": "", "MirrorStatus": "Primary",
        "Settings": {"FlowId": (flowId)}
    }
    For key = "EmailOutput", "OpenOutputFile", "SuspendOnError", "SuspendTerminated", "IsBatch", "RescheduleOnStart" {
        Do body.%Set(key, 0, "boolean")
    }
    Do body.%Set("Expires", 1, "boolean")
    Do body.%Set("OutputFileIsBinary", 1, "boolean")
    Set timing = ##class(sentai.schedule.Timing).ToTaskFields(schedule)
    Set it = timing.%GetIterator()
    While it.%GetNext(.k, .v) { Do body.%Set(k, v, timing.%GetTypeOf(k)) }
    Quit body
}

/// Today when `startTime` (HH:MM) is still ahead (by more than 30 s), otherwise tomorrow.
ClassMethod StartDate(startTime As %String, now As %String = {$HOROLOG}) As %String
{
    Set seconds = ($P(startTime, ":", 1) * 3600) + ($P(startTime, ":", 2) * 60)
    Quit $ZDATE(+now + (seconds <= ($P(now, ",", 2) + 30)), 3)
}

/// Highest platform id among the listed tasks named exactly `name` (ids only grow).
ClassMethod NewestIdNamed(rows As %DynamicArray, name As %String) As %String
{
    Set newest = ""
    Quit:(rows.%ClassName(1) '= "%Library.DynamicArray") ""
    Set it = rows.%GetIterator()
    While it.%GetNext(.k, .row) {
        Continue:'$IsObject(row)
        Continue:(row.%Get("Name") '= name)
        Set id = row.%Get("Id")
        Continue:'##class(sentai.catalog.TaskService).IsTaskId(id)
        Set:((newest = "") || (+id > newest)) newest = +id
    }
    Quit newest
}

/// Deletes the flow's tasks listed in `rows` except `keep`, with the operator's token; `removed`
/// lists the ids deleted, `residue` the refusals (verbatim).
ClassMethod DeleteTasks(flowId As %String, rows As %DynamicArray, token As %String, keep As %String, Output removed As %List, residue As %DynamicArray)
{
    Set removed = ""
    Quit:'$IsObject(rows)
    Set it = rows.%GetIterator()
    While it.%GetNext(.k, .row) {
        Continue:'$IsObject(row)
        Continue:'..IsTaskOf(row.%Get("Name"), flowId)
        Set id = row.%Get("Id")
        Continue:('##class(sentai.catalog.TaskService).IsTaskId(id) || (+id = +keep))
        Set httpStatus = 0
        Try {
            Set answer = ##class(sentai.dispatch.AdminApiClient).Delete("/api/admin/v2/task?id="_(+id), token, .httpStatus)
        } Catch {
            Set answer = "", httpStatus = 0
        }
        If (httpStatus >= 200) && (httpStatus < 300) {
            Set removed = removed_$LB(+id)
        } Else {
            Do residue.%Push({"task": (+id), "detail": ("HTTP "_httpStatus_$S($IsObject(answer) && $IsObject(answer."status"):" "_answer."status"."summary", 1:""))})
        }
    }
}

ClassMethod DeleteSecrets(flowId As %String, generation As %Integer, instances As %List, residue As %DynamicArray = "")
{
    For i = 1:1:$LL(instances) {
        Set instance = $LG(instances, i)
        Continue:(instance = "")
        Set name = ##class(sentai.schedule.Wallet).SecretName(flowId, generation, instance)
        Set sc = ##class(sentai.schedule.Wallet).Delete(name)
        Do:($$$ISERR(sc) && $IsObject(residue)) residue.%Push({"secret": (name), "detail": ($SYSTEM.Status.GetErrorText(sc))})
    }
}

/// The platform's next run for `taskId` ("" when it cannot be read).
ClassMethod NextRun(taskId As %String, token As %String) As %String
{
    Quit:(taskId = "") ""
    Set info = ##class(sentai.catalog.TaskService).PlatformRead("/api/admin/v2/task/info?id="_(+taskId), token)
    Quit $S((info.httpStatus = 200) && $IsObject(info.result):info.result.NextScheduled, 1:"")
}

/// Signs `runAs` in where the password will be used; "" on 200, otherwise the refusal (422).
ClassMethod Verify(baseUrl As %String, instance As %String, runAs As %String, password As %String) As %DynamicObject
{
    Set httpStatus = 0, transportError = ""
    Set answer = ##class(sentai.dispatch.AdminApiClient).Login(baseUrl, runAs, password, .httpStatus, .transportError)
    Quit:(httpStatus = 200) ""
    Set detail = $S(transportError '= "":transportError, $IsObject(answer) && $IsObject(answer."status") && (answer."status"."summary" '= ""):answer."status"."summary", 1:"HTTP "_httpStatus)
    Set out = ..Problem(422, "CREDENTIAL_REFUSED: signing in as '"_runAs_"' on "_instance_" was refused: "_detail)
    Do out.problem.%Set("code", "CREDENTIAL_REFUSED"), out.problem.%Set("instance", instance)
    Quit out
}

/// The distinct targets the flow's steps use, sorted.
ClassMethod TargetsOf(flowId As %String) As %List
{
    Set names = {}
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %EXACT(target) AS target FROM sentai_model.Step WHERE flow = ? AND target IS NOT NULL AND target <> ''", flowId)
    While rs.%Next() { Do names.%Set(rs.%Get("target"), 1) }
    Quit ..Names(names)
}

/// targetPasswords [{target, password}] as {target: password}.
ClassMethod TargetPasswords(list As %DynamicArray) As %DynamicObject
{
    Set out = {}
    Quit:'$IsObject(list) out
    Set it = list.%GetIterator()
    While it.%GetNext(.k, .e) { Do:($IsObject(e) && (e.target '= "")) out.%Set(e.target, e.password) }
    Quit out
}

/// The keys of `map`, sorted.
ClassMethod Names(map As %DynamicObject) As %List
{
    Kill sorted
    Set it = map.%GetIterator()
    While it.%GetNext(.k, .v) { Set sorted(k) = "" }
    Set out = "", k = ""
    For {
        Set k = $O(sorted(k))
        Quit:(k = "")
        Set out = out_$LB(k)
    }
    Quit out
}

ClassMethod JoinArray(a As %DynamicArray) As %String
{
    Set out = ""
    Set it = a.%GetIterator()
    While it.%GetNext(.k, .v) { Set out = out_$S(out = "":"", 1:",")_(+v) }
    Quit out
}

ClassMethod Problem(status As %Integer, detail As %String) As %DynamicObject
{
    Quit ##class(sentai.catalog.TaskService).Problem(status, detail)
}

}
