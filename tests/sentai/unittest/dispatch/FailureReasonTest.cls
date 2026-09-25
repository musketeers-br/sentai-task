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

}
