/// Spec 013 (plan D-1…D-3): a platform-read step runs on a worker with the run's credential for its
/// instance, ends through the locked transition with its report, and never loses its findings when
/// the result must shrink.
Class sentai.unittest.dispatch.ReadExecutorTest Extends sentai.unittest.SentaiTestCase
{

Parameter DASH = "/api/admin/v2/monitor/dashboard/main";

ClassMethod Dashboard(serious As %Integer = 0) As %String
{
    Quit {"status": {"summary": ""}, "result": {"SystemUsage": {"LockTable": "Normal"}, "Alerts": {"SeriousAlerts": (serious), "ApplicationErrors": 0}, "Licensing": {}, "Status": {"UpTime": "1h"}}}.%ToJSON()
}

/// A run of one system alerts check, its step run set to running as StartInProcessStep does.
Method RunningAlertsStep(Output stepRun As sentai.model.StepRun, target As %String = "") As sentai.model.Run
{
    Set step = {"id": "01", "type": "system-alerts-check", "namespace": "%SYS"}
    Do:(target '= "") step.%Set("target", target)
    Set id = ..CreateFlowOf("ReadExec", [(step)])
    Set run = ..DispatchUngated(id)
    Set stepRun = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    If (target '= "") {
        Set stepRun.targetBaseUrl = "https://t.example:52773"
        Do stepRun.%Save()
    }
    $$$ThrowOnError(##class(sentai.model.StepRun).TransitionLocked(stepRun.guid, "running"))
    Quit run
}

Method TestCompletesWithTheReportLocally()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#DASH, "GET", 200, "", ..Dashboard())
    Set run = ..RunningAlertsStep(.sr)
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "LOCAL-TOKEN")
    $$$ThrowOnError(##class(sentai.dispatch.ReadExecutor).Run(sr.guid))
    Set done = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(done.state, "completed")
    Do $$$AssertEquals(done.executedAs, "tester")
    Set report = ##class(%DynamicAbstractObject).%FromJSON(done.result)
    Do $$$AssertEquals(report.type, "system-alerts-check")
    Do $$$AssertEquals(report.instance, "local")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#DASH)), "LOCAL-TOKEN", "read with the run's credential")
}

Method TestReadsTheTargetWithItsCredential()
{
    Set base = "https://t.example:52773"
    Do ##class(sentai.unittest.AdminApiDouble).Script(base_..#DASH, "GET", 200, "", ..Dashboard())
    Set run = ..RunningAlertsStep(.sr, "t1")
    Set ^IRIS.Temp.sentaiTargetCred(run.guid, "t1") = $LB("TARGET-TOKEN", "R", ##class(sentai.dispatch.WaveDispatcher).NowSeconds(), "remote-op", base)
    $$$ThrowOnError(##class(sentai.dispatch.ReadExecutor).Run(sr.guid))
    Set done = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(done.state, "completed")
    Do $$$AssertEquals(done.executedAs, "remote-op")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", base_..#DASH)), "TARGET-TOKEN")
    Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(done.result).instance, "t1")
}

/// A failing check fails the step with its reason and keeps the report.
Method TestFailureKeepsTheReport()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#DASH, "GET", 200, "", ..Dashboard(3))
    Set run = ..RunningAlertsStep(.sr)
    Do ##class(sentai.dispatch.ReadExecutor).Run(sr.guid)
    Set done = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(done.state, "failed")
    Do $$$AssertTrue(done.failureReason [ "3 serious alerts (maximum 0)", done.failureReason)
    Do $$$AssertTrue(done.result [ "SERIOUS_ALERTS_OVER")
}

/// A cancel that wins the race: the worker's late report records nothing.
Method TestCancelBeforeTheWorkerEndsWins()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#DASH, "GET", 200, "", ..Dashboard())
    Set run = ..RunningAlertsStep(.sr)
    $$$ThrowOnError(##class(sentai.model.StepRun).TransitionLocked(sr.guid, "cancelled"))
    Do ##class(sentai.dispatch.ReadExecutor).Run(sr.guid)
    Set done = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(done.state, "cancelled")
    Do $$$AssertEquals(done.result, "")
}

/// An overdue report step is ended by the sweep, like an in-process step.
Method TestOverdueStepIsSwept()
{
    Set run = ..RunningAlertsStep(.sr)
    Set sr = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 4)
    Set sr.timeStarted = $ZDATETIME($H - 1, 3)
    Do sr.%Save()
    Do ##class(sentai.dispatch.WaveDispatcher).SweepTimeouts(run)
    Do $$$AssertEquals(##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0).state, "failed")
}

/// Plan D-3: details are cut first; summary and findings are never cut while details remain.
Method TestFitResultProtectsFindings()
{
    Set report = ##class(sentai.steps.reports.Report).NewReport("web-app-inventory")
    For i = 1:1:5 { Do ##class(sentai.steps.reports.Report).AddFinding(report, "high", "RULE", "item"_i, "detail") }
    Set apps = []
    For i = 1:1:400 { Do apps.%Push({"path": ("/app/"_i), "namespace": "USER", "authenticationMethods": ["Password"]}) }
    Set report.details = {"applications": (apps)}
    Set fitted = ##class(sentai.dispatch.ReadExecutor).FitResult(report.%ToJSON(), "summary,findings")
    Do $$$AssertTrue($L(fitted) <= 8000, $L(fitted))
    Set obj = ##class(%DynamicAbstractObject).%FromJSON(fitted)
    Do $$$AssertEquals(obj.findings.%Size(), 5, "every finding kept")
    Do $$$AssertEquals(obj.truncated, 1)
    Do $$$AssertTrue(obj.omitted > 0)
    Do $$$AssertTrue(obj.details.applications.%Size() < 400)
}

/// SC-004: no password, hash, token or secret value in any stored report, from any type.
Method TestNoSecretInAnyReport()
{
    Set leak = "LEAK-"_$SYSTEM.Util.CreateGUID()
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/security/users", "GET", 200, "", {"result": [{"Name": "u", "Enabled": true, "Password": (leak)}]}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/security/user?name=u", "GET", 200, "", {"result": {"Roles": [], "Password": (leak), "PasswordHash": (leak)}}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/security/services", "GET", 200, "", {"result": [{"Name": "s", "Enabled": true, "AuthenticationMethods": [], "Secret": (leak)}]}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/security/audit/enabled", "GET", 200, "", {"result": {"Enabled": true}}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/web-apps", "GET", 200, "", {"result": [{"Name": "/a", "Enabled": true, "Password": (leak)}]}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wallet/collections", "GET", 200, "", {"result": [{"Name": "c", "UseResource": "%R", "Secret": (leak)}]}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wallet/secrets?collection=c", "GET", 200, "", {"result": [{"Name": "k", "Type": "KeyValue", "Secret": (leak), "Value": (leak)}]}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#DASH, "GET", 200, "", {"result": {"Alerts": {}, "SystemUsage": {"X": (leak)}}}.%ToJSON())
    For type = "security-posture-report", "web-app-inventory", "secrets-inventory" {
        Do ##class(sentai.dispatch.ReadExecutor).Build(type, {}, ##class(sentai.steps.reports.Reader).For("", "t"), .report)
        Do $$$AssertNotTrue(report.%ToJSON() [ leak, type_" carries no secret")
    }
}

}
