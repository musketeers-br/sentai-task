/// Spec 006 T005 — suspend/resume on the contract proven on the platform (research R-3):
/// POST task/suspend|resume?id= with a JSON body `{}`, then a re-read decides the answer.
Class sentai.unittest.catalog.TaskSuspendTest Extends sentai.unittest.SentaiTestCase
{

/// Scripts the platform call and the task's re-read (single + info with `suspendedAfter`).
ClassMethod ScriptCall(action As %String, httpStatus As %Integer, suspendedAfter As %Boolean = 1, body As %String = "")
{
    Set body = $S(body '= "":body, 1:##class(sentai.unittest.catalog.CatalogFixtures).Envelope({}))
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/"_action, "POST", httpStatus, "", body)
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(1003, "SentaiTask: 1#01", "sentai.dispatch.ScheduledFlowTask", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(suspendedAfter), "IRISAPP")
}

Method TestSuspendPostsTheProvenPathWithAJsonBody()
{
    Do ..ScriptCall("suspend", 200, 1)
    Do ##class(sentai.catalog.TaskService).SetSuspended(1003, 1, "fake-token")
    Do $$$AssertEquals($G(^sentaiTestDouble("posted", "/api/admin/v2/task/suspend")), $LB("/api/admin/v2/task/suspend?id=1003", "{}"))
}

Method TestResumePostsTheResumePath()
{
    Do ..ScriptCall("resume", 200, 0)
    Do ##class(sentai.catalog.TaskService).SetSuspended(1003, 0, "fake-token")
    Do $$$AssertEquals($G(^sentaiTestDouble("posted", "/api/admin/v2/task/resume")), $LB("/api/admin/v2/task/resume?id=1003", "{}"))
    Do $$$AssertEquals($D(^sentaiTestDouble("posted", "/api/admin/v2/task/suspend")), 0)
}

Method TestAppliedStateAnswers200WithTheReReadTask()
{
    Do ..ScriptCall("suspend", 200, 1)
    Set out = ##class(sentai.catalog.TaskService).SetSuspended(1003, 1, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertEquals(out.body.taskId, 1003)
    Do $$$AssertTrue(out.body.suspended)
    Do $$$AssertTrue($D(^sentaiTestDouble("gets", "/api/admin/v2/task/info?id=1003")), "re-read after the call")
}

Method TestAcceptedButNotAppliedIs502WithThePlatformsRead()
{
    Do ..ScriptCall("suspend", 200, 0)
    Set out = ##class(sentai.catalog.TaskService).SetSuspended(1003, 1, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertEquals($EXTRACT(out.problem.detail, 1, 19), "SUSPEND_NOT_APPLIED")
    Do $$$AssertEquals(out.problem.platformInfo.%Get("Suspended"), 0)
    Do $$$AssertEquals(out.problem.platformInfo.%GetTypeOf("Suspended"), "boolean")
}

Method TestRefusalIsVerbatimWithoutReRead()
{
    Do ..ScriptCall("suspend", 403)
    Set out = ##class(sentai.catalog.TaskService).SetSuspended(1003, 1, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.detail, "")
    Do $$$AssertEquals(out.problem.platformStatus.%ToJSON(), "{""errors"":[],""summary"":""""}")
    Do $$$AssertEquals($D(^sentaiTestDouble("gets")), 0, "no re-read after a refusal")
}

Method TestUnknownTaskIs404Verbatim()
{
    Do ..ScriptCall("suspend", 404, 1, ##class(sentai.unittest.catalog.CatalogFixtures).NotFoundJSON(99999))
    Set out = ##class(sentai.catalog.TaskService).SetSuspended(99999, 1, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 404)
    Do $$$AssertEquals(out.problem.detail, "ERROR #5809: Object to Load not found, class '%SYS.Task', ID '99999'")
}

Method TestNonBooleanIs400AndMissingBodyMeansSuspend()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"suspended": "yes"}.%ToJSON())
    Do ##class(sentai.rest.Dispatcher).SuspendCatalogTask(1003)
    Do $$$AssertEquals(%response.Status, 400)
    Do $$$AssertEquals($D(^sentaiTestDouble("posted")), 0, "no platform call")

    Do ..ScriptCall("suspend", 200, 1)
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).SuspendCatalogTask(1003)
    Do $$$AssertEquals(%response.Status, 200)
    Do $$$AssertTrue($D(^sentaiTestDouble("posted", "/api/admin/v2/task/suspend")), "no body → suspend, as before")
}

}
