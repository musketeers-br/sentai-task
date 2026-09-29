/// Spec 015 T005, T012 (plan D-1, D-2, D-4): scheduling, reading and unscheduling a flow through
/// the platform's management API with the operator's token, with the run-as passwords verified by
/// signing in and kept only in the wallet (here the double records the wallet writes by name).
/// Nothing here creates a real task or secret.
Class sentai.unittest.schedule.ScheduleServiceTest Extends sentai.unittest.SentaiTestCase
{

Parameter PASSWORD = "pw-015-never-stored";

Parameter TASKID = 42;

Parameter NEXTRUN = "2026-10-03 03:00:00";

Parameter BASE = "https://sched.example:52773";

Method OneStepFlow(prefix As %String = "Sched") As %String
{
    Quit ..CreateFlowOf(prefix, [{"id": "01", "type": "db-size-report"}])
}

ClassMethod Body(runAs As %String = "sched-test", targets As %DynamicArray = "") As %DynamicObject
{
    Set:(targets = "") targets = []
    Quit {"schedule": {"kind": "weekly", "days": [6], "startTime": "03:00"}, "runAs": (runAs), "password": (..#PASSWORD), "targetPasswords": (targets)}
}

ClassMethod TaskName(flowId As %String) As %String
{
    Quit ##class(sentai.schedule.ScheduleService).TaskName(flowId, ##class(sentai.model.Flow).%OpenId(flowId, 0).name)
}

/// The platform after a create: the new task (TASKID) plus `extra` rows; its next run.
ClassMethod ScriptPlatform(flowId As %String, extra As %DynamicArray = "", taskId As %Integer = {..#TASKID})
{
    Set rows = [{"Id": (taskId), "Name": (..TaskName(flowId))}]
    If $IsObject(extra) {
        Set it = extra.%GetIterator()
        While it.%GetNext(.k, .r) { Do rows.%Push(r) }
    }
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 200, "", "{""result"":{}}")
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", {"result": (rows)}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/info?id="_taskId, "GET", 200, "", {"result": {"NextScheduled": (..#NEXTRUN)}}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "DELETE", 200, "", "{""result"":{}}")
}

ClassMethod Secrets() As %String
{
    Set out = "", k = ""
    For {
        Set k = $O(^sentaiTestDouble("wallet", k))
        Quit:(k = "")
        Set out = out_$S(out = "":"", 1:",")_k
    }
    Quit out
}

ClassMethod TaskCreates() As %DynamicArray
{
    Set out = []
    For i = 1:1:+$G(^sentaiTestDouble("postlog")) {
        Set e = ^sentaiTestDouble("postlog", i)
        Do:($LG(e, 1) = "/api/admin/v2/task") out.%Push({}.%FromJSON($LG(e, 2)))
    }
    Quit out
}

Method TestHappyPathCreatesOneTaskAndStoresNoPassword()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 201, $S(out.%IsDefined("problem"):out.problem.%ToJSON(), 1:""))
    Do $$$AssertEquals(out.body.taskId, ..#TASKID)
    Do $$$AssertEquals(out.body.nextRun, ..#NEXTRUN)
    Do $$$AssertEquals(out.body.describe, "Weekly on Sat at 03:00")

    // Verified by signing in on this instance as the run-as account.
    Do $$$AssertEquals($G(^sentaiTestDouble("login", "primary")), "sched-test")
    // One secret, generation 1, holding the user (the double records only the user).
    Do $$$AssertEquals(..Secrets(), ##class(sentai.schedule.Wallet).SecretName(id, 1, "primary"))
    Do $$$AssertEquals(^sentaiTestDouble("wallet", ##class(sentai.schedule.Wallet).SecretName(id, 1, "primary")), "sched-test")

    // One task, created with the operator's token, run as the run-as account.
    Set creates = ..TaskCreates()
    Do $$$AssertEquals(creates.%Size(), 1)
    Set body = creates.%Get(0)
    Do $$$AssertEquals(body.Name, ..TaskName(id))
    Do $$$AssertEquals(body.RunAsUser, "sched-test")
    Do $$$AssertEquals(body.TaskClass, "sentai.dispatch.ScheduledFlowTask")
    Do $$$AssertEquals(body.Settings.FlowId, id)
    Do $$$AssertNotTrue(body.Settings.%IsDefined("StepId"))
    Do $$$AssertEquals(body.TimePeriod, "Weekly")
    Do $$$AssertEquals(body.TimePeriodDay, "7")
    Do $$$AssertEquals(body.DailyStartTime, "03:00:00")
    Do $$$AssertEquals($LG(^sentaiTestDouble("postlog", 1), 3), "operator-token")
    Do $$$AssertNotTrue(body.%ToJSON() [ ..#PASSWORD)

    Set s = ##class(sentai.model.Schedule).FlowIndexOpen(id, 0)
    Do $$$AssertTrue($IsObject(s))
    Do $$$AssertEquals(s.taskId, ..#TASKID)
    Do $$$AssertEquals(s.generation, 1)
    Do $$$AssertEquals(s.days, "6")
    Do $$$AssertEquals(s.nextRun, ..#NEXTRUN)
    Do $$$AssertEquals(s.createdBy, "operator")
    Do $$$AssertEquals(##class(sentai.model.Flow).%OpenId(id, 0).scheduleSpec, "Weekly on Sat at 03:00")
    Do $$$AssertNotTrue(out.body.%ToJSON() [ ..#PASSWORD)
}

Method TestRefusedPasswordStoresNothing()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/login", "POST", 401, "", "{""status"":{""errors"":[],""summary"":""Invalid credentials""}}")
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 422)
    Do $$$AssertEquals(out.problem.code, "CREDENTIAL_REFUSED")
    Do $$$AssertEquals(out.problem.instance, "primary")
    Do $$$AssertTrue(out.problem.detail [ "Invalid credentials")
    Do $$$AssertEquals(..Secrets(), "")
    Do $$$AssertEquals(..TaskCreates().%Size(), 0)
    Do $$$AssertNotTrue($IsObject(##class(sentai.model.Schedule).FlowIndexOpen(id, 0)))
}

Method TestTaskCreateRefusalRemovesTheNewSecretsAndIsVerbatim()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 403, "", "{""status"":{""errors"":[{""error"":""ERROR #5001: no""}],""summary"":""ERROR #5001: no""}}")
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.platformStatus.summary, "ERROR #5001: no")
    Do $$$AssertEquals(..Secrets(), "")
    Do $$$AssertNotTrue($IsObject(##class(sentai.model.Schedule).FlowIndexOpen(id, 0)))
}

Method TestWalletRefusalIsReported()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Set ^sentaiTestDouble("walletRefused") = "ERROR #822: Access Denied"
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.code, "WALLET_REFUSED")
    Do $$$AssertTrue(out.problem.detail [ "#822")
    Do $$$AssertEquals(..TaskCreates().%Size(), 0)
}

Method TestUnconfirmedCreateRollsBack()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", "{""result"":[]}")
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertTrue(out.problem.detail [ "SCHEDULE_NOT_CONFIRMED")
    Do $$$AssertEquals(..Secrets(), "")
}

Method TestInvalidScheduleAndOldBody()
{
    Set id = ..OneStepFlow()
    Set body = ..Body()
    Set body.schedule = {"kind": "monthly", "dayOfMonth": 32, "startTime": "03:00"}
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, body, "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 400)
    Do $$$AssertEquals(out.problem.code, "SCHEDULE_INVALID")
    Do $$$AssertEquals(out.problem.field, "dayOfMonth")

    // The spec 001 body is refused over the endpoint with the new shape named.
    Do ##class(sentai.unittest.schedule.ScheduleServiceTest).Request({"scheduleSpec": "WEEKLY SAT 03:00"})
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 400)
    Do $$$AssertEquals(+$G(^sentaiTestDouble("postlog")), 0)
}

/// FR-007: destructive steps stay unschedulable; in-process steps are schedulable now (D-6).
Method TestDestructiveRefusedInProcessAllowed()
{
    Set id = ..CreateCanonicalFlow("SchedDestructive")
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 422)
    Do $$$AssertTrue(out.body.%ToJSON() [ "DESTRUCTIVE_NOT_SCHEDULABLE")
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
    Do $$$AssertEquals(..Secrets(), "")

    Set id = ..OneStepFlow("SchedInProc")
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Do $$$AssertNotTrue(report.%ToJSON() [ "IN_PROCESS_NOT_SCHEDULABLE")
}

Method TestTargetPasswordsMustMatchTheFlowsTargets()
{
    Set target = ##class(sentai.unittest.targets.TargetServiceTest).Unique("sched")
    Do ##class(sentai.targets.TargetService).Create({"name": (target), "baseUrl": (..#BASE)}, "tester")
    Set id = ..CreateFlowOf("SchedTarget", [{"id": "01", "type": "integrity-check", "namespace": "USER", "target": (target)}])
    Do ..ScriptPlatform(id)

    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 400)
    Do $$$AssertEquals(out.problem.code, "TARGET_PASSWORDS_MISMATCH")

    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(, [{"target": (target), "password": "pw-target"}]), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 201, $S(out.%IsDefined("problem"):out.problem.%ToJSON(), 1:out.body.%ToJSON()))
    Do $$$AssertEquals($G(^sentaiTestDouble("login", ..#BASE)), "sched-test", "verified on the target")
    Do $$$AssertTrue($D(^sentaiTestDouble("wallet", ##class(sentai.schedule.Wallet).SecretName(id, 1, target))))
    Do $$$AssertEquals(##class(sentai.model.Schedule).FlowIndexOpen(id, 0).targets, target)
}

/// Replace: a new generation of secrets and one new task; the old task, the legacy per-step tasks
/// and the old secrets are removed.
Method TestReplaceKeepsOneTaskAndRemovesLegacyTasks()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator").httpStatus, 201)

    Do ..ScriptPlatform(id, [{"Id": (..#TASKID), "Name": (..TaskName(id))}, {"Id": 17, "Name": ("SentaiTask: "_id_"#01")}, {"Id": 18, "Name": "SentaiTask: 999999 other flow"}], 43)
    Set body = ..Body()
    Set body.schedule = {"kind": "daily", "startTime": "05:00"}
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, body, "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 201)
    Do $$$AssertEquals(out.body.taskId, 43)
    Do $$$AssertEquals($G(^sentaiTestDouble("deleted", "/api/admin/v2/task?id="_..#TASKID)), "operator-token")
    Do $$$AssertEquals($G(^sentaiTestDouble("deleted", "/api/admin/v2/task?id=17")), "operator-token")
    Do $$$AssertEquals($D(^sentaiTestDouble("deleted", "/api/admin/v2/task?id=18")), 0, "another flow's task stays")
    Do $$$AssertEquals($D(^sentaiTestDouble("deleted", "/api/admin/v2/task?id=43")), 0)
    Do $$$AssertEquals(..Secrets(), ##class(sentai.schedule.Wallet).SecretName(id, 2, "primary"))
    Set s = ##class(sentai.model.Schedule).FlowIndexOpen(id, 0)
    Do $$$AssertEquals(s.generation, 2)
    Do $$$AssertEquals(s.kind, "daily")
    Do $$$AssertEquals(s.taskId, 43)
}

/// A failure while creating the new task keeps the old schedule working.
Method TestFailedReplaceKeepsTheOldSchedule()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator").httpStatus, 201)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 403, "", "{""status"":{""errors"":[],""summary"":""refused""}}")
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals($D(^sentaiTestDouble("deleted")), 0, "no task deleted")
    Do $$$AssertEquals(..Secrets(), ##class(sentai.schedule.Wallet).SecretName(id, 1, "primary"))
    Do $$$AssertEquals(##class(sentai.model.Schedule).FlowIndexOpen(id, 0).generation, 1)
}

Method TestResidueIsReportedWhenAnOldDeleteIsRefused()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id, [{"Id": 17, "Name": ("SentaiTask: "_id_"#01")}])
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "DELETE", 403, "", "{""status"":{""errors"":[],""summary"":""not yours""}}")
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 201)
    Do $$$AssertEquals(out.body.residue.%Size(), 1)
    Do $$$AssertEquals(out.body.residue.%Get(0).task, 17)
    Do $$$AssertTrue(out.body.residue.%Get(0).detail [ "not yours")
}

Method TestReadReturnsLiveNextRunAndLastRun()
{
    Set id = ..OneStepFlow()
    Set out = ##class(sentai.schedule.ScheduleService).Read(id, "operator-token")
    Do $$$AssertEquals(out.body.scheduled, 0)
    Do $$$AssertTrue(out.body.instanceTime '= "")

    Do ..ScriptPlatform(id)
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator").httpStatus, 201)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/info?id="_..#TASKID, "GET", 200, "", {"result": {"NextScheduled": "2026-10-10 03:00:00"}}.%ToJSON())
    Set run = ..DispatchUngated(id)
    Set run.trigger = "scheduled"
    Do run.%Save()

    Set out = ##class(sentai.schedule.ScheduleService).Read(id, "operator-token")
    Do $$$AssertEquals(out.body.scheduled, 1)
    Do $$$AssertEquals(out.body.nextRun, "2026-10-10 03:00:00")
    Do $$$AssertEquals(out.body.runAs, "sched-test")
    Do $$$AssertEquals(out.body.schedule.days.%Get(0), 6)
    Do $$$AssertEquals(out.body.lastRun.guid, run.guid)
    Do $$$AssertEquals(##class(sentai.model.Schedule).FlowIndexOpen(id, 0).nextRun, "2026-10-10 03:00:00", "the list's copy is refreshed (D-8)")
}

Method TestUnscheduleRemovesEverythingAndIsIdempotent()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator").httpStatus, 201)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", {"result": [{"Id": (..#TASKID), "Name": (..TaskName(id))}, {"Id": 17, "Name": ("SentaiTask: "_id_"#01")}]}.%ToJSON())

    Set out = ##class(sentai.schedule.ScheduleService).Unschedule(id, "operator-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertEquals(out.body.removedTasks.%Size(), 2)
    Do $$$AssertEquals(out.body.removedSecrets, 1)
    Do $$$AssertEquals(..Secrets(), "")
    Do $$$AssertNotTrue($IsObject(##class(sentai.model.Schedule).FlowIndexOpen(id, 0)))
    Do $$$AssertEquals(##class(sentai.model.Flow).%OpenId(id, 0).scheduleSpec, "")

    Kill ^sentaiTestDouble("deleted")
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", "{""result"":[]}")
    Set out = ##class(sentai.schedule.ScheduleService).Unschedule(id, "operator-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertEquals(out.body.removedTasks.%Size(), 0)
    Do $$$AssertEquals(out.body.removedSecrets, 0)
}

Method TestFlowListNextRunComesFromTheSchedule()
{
    Set id = ..OneStepFlow()
    Do ..ScriptPlatform(id)
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).Schedule(id, ..Body(), "operator-token", "operator").httpStatus, 201)
    Set %response = ##class(%CSP.Response).%New()
    Set out = ..Capture("ListFlows")
    Set found = ""
    Set it = out.%GetIterator()
    While it.%GetNext(.k, .f) { Set:(f.id = id) found = f.nextRun }
    Do $$$AssertEquals(found, ..#NEXTRUN)
}

/// The spec 015 task-name form resolves to its flow; the catalog's destructiveness is the flow's.
Method TestTaskOriginReadsTheFlowForm()
{
    Set id = ..OneStepFlow()
    Set origin = ##class(sentai.catalog.TaskOrigin).Resolve(..TaskName(id))
    Do $$$AssertEquals(origin.flowId, id)
    Do $$$AssertNotTrue(origin.%IsDefined("stepId"))
    Do $$$AssertTrue(origin.flowExists)
    Set task = {"class": "sentai.dispatch.ScheduledFlowTask", "origin": (origin)}
    Do ##class(sentai.catalog.TaskShape).ApplyDestructiveness(task)
    Do $$$AssertEquals(task.destructive, 0)
    Do $$$AssertEquals(task.destructiveUnknown, 0)
    Set legacy = ##class(sentai.catalog.TaskOrigin).Resolve("SentaiTask: "_id_"#01")
    Do $$$AssertEquals(legacy.stepId, "01")
}

/// The platform refuses a start in the past: a time already gone today starts tomorrow.
Method TestStartDateIsTomorrowWhenTodaysTimeHasPassed()
{
    Set day = 67842
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).StartDate("04:00", day_",36000"), $ZDATE(day + 1, 3))
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).StartDate("11:00", day_",36000"), $ZDATE(day, 3))
    Do $$$AssertEquals(##class(sentai.schedule.ScheduleService).StartDate("10:00", day_",35990"), $ZDATE(day + 1, 3), "within 30 s counts as passed")
}

ClassMethod Request(bodyObj As %DynamicObject)
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write(bodyObj.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
}

/// Runs a Dispatcher handler and returns the JSON it wrote.
ClassMethod Capture(handler As %String) As %DynamicAbstractObject
{
    Set io = $IO, file = ##class(%File).TempFilename("json")
    Open file:("NW"):2
    Use file
    Do $CLASSMETHOD("sentai.rest.Dispatcher", handler)
    Close file
    Use io
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set out = {}.%FromJSON(stream)
    Do ##class(%File).Delete(file)
    Quit out
}

}
