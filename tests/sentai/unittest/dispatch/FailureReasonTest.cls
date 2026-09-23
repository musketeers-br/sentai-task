Class sentai.unittest.dispatch.FailureReasonTest Extends sentai.unittest.SentaiTestCase
{

Method TestFailureReasonIsStoredVerbatimFromAdminApi()
{
    Set id = ..CreateCanonicalFlow("FailureReasonFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .report)
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

}
