/// Spec 015 T006, T014, T016 (plan D-3, D-5): a flow's task firing. Sign-ins use the stored wallet
/// secrets (the double answers for them); a started run is marked `scheduled` and holds the
/// run-as credential; a run that cannot start is recorded as a failed run with one log entry.
Class sentai.unittest.schedule.ScheduledStartTest Extends sentai.unittest.SentaiTestCase
{

Parameter BASE = "https://fire.example:52773";

/// A schedule row for `flowId` as ScheduleService writes it (generation 1).
ClassMethod ScheduleRow(flowId As %String, targets As %String = "") As sentai.model.Schedule
{
    Set s = ##class(sentai.model.Schedule).%New()
    Do s.flowSetObjectId(flowId)
    Set s.kind = "daily", s.startTime = "03:00", s.runAs = "sched-test", s.generation = 1, s.taskId = 42, s.targets = targets
    Do s.%Save()
    Quit s
}

ClassMethod ScriptLogin(baseUrl As %String = "", access As %String = "AT-1")
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(baseUrl_"/api/admin/login", "POST", 200, "", {"access_token": (access), "refresh_token": ("R"_access), "sub": "sched-test"}.%ToJSON())
}

ClassMethod LastRun(flowId As %String) As sentai.model.Run
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM sentai_model.Run WHERE flow = ? ORDER BY ID DESC", flowId)
    Quit:'rs.%Next() ""
    Quit ##class(sentai.model.Run).%OpenId(rs.%Get("ID"), 0)
}

ClassMethod Messages(run As sentai.model.Run) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT severity, message FROM sentai_model.LogEntry WHERE run = ? ORDER BY ID", run.%Id())
    While rs.%Next() { Do out.%Push({"severity": (rs.%Get("severity")), "message": (rs.%Get("message"))}) }
    Quit out
}

ClassMethod StepRunCount(run As sentai.model.Run) As %Integer
{
    Set runId = run.%Id()
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.StepRun WHERE run = :runId)
    Quit +$G(n)
}

Method OneStepFlow() As %String
{
    Quit ..CreateFlowOf("Fire", [{"id": "01", "type": "db-size-report"}])
}

Method TestFiringStartsAScheduledRunAsTheRunAsAccount()
{
    Set id = ..OneStepFlow()
    Do ..ScheduleRow(id)
    Do ..ScriptLogin()
    Set sc = ##class(sentai.schedule.ScheduledStart).Fire(id)
    Do $$$AssertStatusOK(sc)

    Do $$$AssertEquals(^sentaiTestDouble("loginSecret", "primary"), ##class(sentai.schedule.Wallet).SecretName(id, 1, "primary"))
    Set run = ..LastRun(id)
    Do $$$AssertTrue($IsObject(run))
    Do $$$AssertEquals(run.trigger, "scheduled")
    Do $$$AssertEquals(run.dispatchedBy, "sched-test")
    Do $$$AssertEquals(run.state, "running")
    Do $$$AssertEquals(..StepRunCount(run), 1)
    Set first = ..Messages(run).%Get(0)
    Do $$$AssertEquals(first.message, "Run started by the schedule of flow "_##class(sentai.model.Flow).%OpenId(id, 0).name_" as sched-test (flow revision 1, 1 step)")
    // E-1: the run holds the run-as pair and renews it.
    Do $$$AssertEquals(^sentaiRun(run.guid, "%token"), "AT-1")
    Do $$$AssertEquals(^sentaiRun(run.guid, "%refresh"), "RAT-1")
    Do $$$AssertEquals(^sentaiTestDouble("backgroundLoop", run.guid), 1)
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).ShapeRun(run, 0).trigger, "scheduled")
}

Method TestUnreadableSecretRecordsAStartFailure()
{
    Set id = ..OneStepFlow()
    Do ..ScheduleRow(id)
    Do ##class(sentai.unittest.AdminApiDouble).ScriptSecretRefused(##class(sentai.schedule.Wallet).SecretName(id, 1, "primary"))
    Set sc = ##class(sentai.schedule.ScheduledStart).Fire(id)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "#822")

    Set run = ..LastRun(id)
    Do $$$AssertEquals(run.state, "failed")
    Do $$$AssertEquals(run.trigger, "scheduled")
    Do $$$AssertEquals(run.dispatchedBy, "sched-test")
    Do $$$AssertEquals(run.startedAt, run.finishedAt)
    Do $$$AssertEquals(..StepRunCount(run), 0)
    Set log = ..Messages(run)
    Do $$$AssertEquals(log.%Size(), 1)
    Do $$$AssertEquals(log.%Get(0).severity, "error")
    Do $$$AssertEquals(log.%Get(0).message, "Scheduled run could not start: could not read the stored credential for primary: ERROR #822: Access Denied")
}

Method TestRefusedSignInRecordsAStartFailure()
{
    Set id = ..OneStepFlow()
    Do ..ScheduleRow(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/login", "POST", 401, "", "{""status"":{""errors"":[],""summary"":""Invalid credentials""}}")
    Do $$$AssertStatusNotOK(##class(sentai.schedule.ScheduledStart).Fire(id))
    Set log = ..Messages(..LastRun(id))
    Do $$$AssertEquals(log.%Get(0).message, "Scheduled run could not start: could not sign in to primary: HTTP 401 Invalid credentials")
}

Method TestInvalidFlowListsEveryError()
{
    Set id = ..CreateFlowOf("FireInvalid", [{"id": "01", "type": "custom", "taskName": "Custom"}, {"id": "02", "type": "custom", "taskName": "Custom"}])
    Do ..ScheduleRow(id)
    Do ..ScriptLogin()
    Do $$$AssertStatusNotOK(##class(sentai.schedule.ScheduledStart).Fire(id))
    Set run = ..LastRun(id)
    Do $$$AssertEquals(run.state, "failed")
    Set text = ..Messages(run).%Get(0).message
    Do $$$AssertTrue(text [ "Scheduled run could not start: the flow does not validate: ", text)
    Do $$$AssertTrue((text [ "#01 CUSTOM_CLASS_REQUIRED") && (text [ "#02 CUSTOM_CLASS_REQUIRED"), text)
}

Method TestTargetCredentialsAreStoredForTheRun()
{
    Set target = ##class(sentai.unittest.targets.TargetServiceTest).Unique("fire")
    Do ##class(sentai.targets.TargetService).Create({"name": (target), "baseUrl": (..#BASE)}, "tester")
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/info", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": {"serverVersion": "IRIS 2026.2", "username": "sched-test", "namespaces": [{"name": "%SYS"}, {"name": "USER"}]}}.%ToJSON())
    Set id = ..CreateFlowOf("FireTarget", [{"id": "01", "type": "integrity-check", "namespace": "USER", "target": (target)}])
    Do ..ScheduleRow(id, target)
    Do ..ScriptLogin()
    Do ..ScriptLogin(..#BASE, "TAT")
    Set sc = ##class(sentai.schedule.ScheduledStart).Fire(id)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertEquals(^sentaiTestDouble("loginSecret", ..#BASE), ##class(sentai.schedule.Wallet).SecretName(id, 1, target))
    Set run = ..LastRun(id)
    Do $$$AssertEquals(run.state, "running")
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).TargetToken(run.guid, target), "TAT")
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).TargetBaseUrl(run.guid, target), ..#BASE)
}

/// A target that does not answer at firing: the run starts; its steps there fail as in any run.
Method TestTargetDownStillStartsTheRun()
{
    Set target = ##class(sentai.unittest.targets.TargetServiceTest).Unique("fire")
    Do ##class(sentai.targets.TargetService).Create({"name": (target), "baseUrl": (..#BASE)}, "tester")
    Set id = ..CreateFlowOf("FireDown", [{"id": "01", "type": "integrity-check", "namespace": "USER", "target": (target)}])
    Do ..ScheduleRow(id, target)
    Do ..ScriptLogin()
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: connection refused")
    Do $$$AssertStatusOK(##class(sentai.schedule.ScheduledStart).Fire(id))
    Set run = ..LastRun(id)
    Do $$$AssertEquals(run.state, "running")
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).TargetToken(run.guid, target), "")
}

Method TestLegacyTaskDoesNothingAndAMissingScheduleIsAnError()
{
    Set id = ..OneStepFlow()
    Set task = ##class(sentai.dispatch.ScheduledFlowTask).%New()
    Set task.FlowId = id, task.StepId = "01", task.IsRoot = 1
    Do $$$AssertStatusOK(task.OnTask())
    Do $$$AssertNotTrue($IsObject(..LastRun(id)))

    Set task = ##class(sentai.dispatch.ScheduledFlowTask).%New()
    Set task.FlowId = id
    Set sc = task.OnTask()
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "has no schedule")
}

}
