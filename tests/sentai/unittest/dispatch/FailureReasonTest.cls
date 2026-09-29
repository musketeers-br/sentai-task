Class sentai.unittest.dispatch.FailureReasonTest Extends sentai.unittest.SentaiTestCase
{

Method TestFailureReasonIsStoredVerbatimFromAdminApi()
{
    Set id = ..CreateCanonicalFlow("FailureReasonFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")

    Set weirdMessage = "  Some Verbatim Text -- with (parentheses) and a trailing period.  "
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v1/async-result?id=fake123", "GET", 200, "",
        "{""result"":{""State"":""Error""},""status"":{""summary"":"""_weirdMessage_"""}}")

    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set sr.adminJobId = "/api/admin/v1/async-result?id=fake123"
    Do sr.TransitionTo("running")

    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "fake-token")

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(refreshed.state, "failed")
    Do $$$AssertEquals(refreshed.failureReason, weirdMessage)
}

/// E-1 as documented in README "Known limitations": a status check made after the run's 60 s
/// credential expired gets 401 — the step must fail with that recorded, not stay "running"
/// forever (which left the run itself unable to ever terminate).
Method TestUnauthorizedStatusCheckFailsTheStep()
{
    Set id = ..CreateCanonicalFlow("UnauthorizedPollFixture")
    Set run = ..DispatchUngated(id)

    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v1/async-result?id=expired1", "GET", 401, "", "")
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set sr.adminJobId = "/api/admin/v1/async-result?id=expired1"
    Do sr.TransitionTo("running")

    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "expired-token")

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(refreshed.state, "failed")
    Do $$$AssertTrue(refreshed.failureReason [ "HTTP 401", "failure reason records the platform's 401")
}

/// Spec 011 T025 (D2): IRIS 2026.2 puts the job's own reason in result.FailureReason with an empty
/// status.summary (spec 011 evidence t001-demo-role.md, round 4). It must be the step's reason,
/// verbatim, not "Administrative job reported Failed".
Method TestJobFailureReasonFromResultIsVerbatim()
{
    Set id = ..CreateCanonicalFlow("JobFailureReasonFixture")
    Set run = ..DispatchUngated(id)
    Set reason = "ERROR #5002: ObjectScript error: <PROTECT>%SaveData+4^SYS.BackgroundIntegrity.1 ^%SYS.BackgroundTaskD,/usr/irissys/mgr/"
    Set body = {"status": {"errors": [], "summary": ""}, "console": [], "result": {"State": "Failed", "TaskName": "POST /v2/database-dir/integrity-check", "FailureReason": (reason)}}
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v1/async-result?id=failed1", "GET", 200, "", body.%ToJSON())
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set sr.adminJobId = "/api/admin/v1/async-result?id=failed1"
    Do sr.TransitionTo("running")

    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "fake-token")

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(refreshed.state, "failed")
    Do $$$AssertEquals(refreshed.failureReason, reason)
}

/// Neither a FailureReason nor a summary: the generic text stays.
Method TestJobFailureWithoutAnyReasonKeepsTheGenericText()
{
    Set id = ..CreateCanonicalFlow("JobFailureNoReasonFixture")
    Set run = ..DispatchUngated(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v1/async-result?id=failed2", "GET", 200, "", "{""status"":{""summary"":""""},""result"":{""State"":""Failed""}}")
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set sr.adminJobId = "/api/admin/v1/async-result?id=failed2"
    Do sr.TransitionTo("running")
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "fake-token")
    Do $$$AssertEquals(##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0).failureReason, "Administrative job reported Failed")
}

}
