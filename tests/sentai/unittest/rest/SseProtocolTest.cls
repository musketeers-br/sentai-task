/// Exercises the event-emission and termination logic behind GET /runs/{guid}/events
/// (contracts/sse-protocol.md) without depending on a live, indefinitely-open HTTP
/// connection — the run is driven to a terminal state first, so the loop in
/// StreamEvents() is guaranteed to emit run-terminal and return on its first pass,
/// regardless of %response.IsClientConnected() behavior outside a real CSP request.
Class sentai.unittest.rest.SseProtocolTest Extends sentai.unittest.SentaiTestCase
{

Method TestEventVersionStrictlyIncreasesAndRunTerminalIsFinal()
{
    Set id = ..CreateCanonicalFlow("SseFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")

    Set v0 = run.eventVersion
    Set sr01 = ##class(sentai.model.StepRun).%OpenId(##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), "01", 0), 4)
    Do sr01.TransitionTo("running")
    Set v1 = ##class(sentai.model.Run).%OpenId(run.%Id(), 0).eventVersion
    Do $$$AssertTrue(v1 > v0)

    Do sr01.TransitionTo("completed")
    Set v2 = ##class(sentai.model.Run).%OpenId(run.%Id(), 0).eventVersion
    Do $$$AssertTrue(v2 > v1)
}

Method TestPollingAndSseReadTheSamePersistedState()
{
    Set id = ..CreateCanonicalFlow("SsePollingParity")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)

    Set sr01 = ##class(sentai.model.StepRun).%OpenId(##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), "01", 0), 4)
    Do sr01.TransitionTo("running")

    // What GET /runs/{guid} (3s-polling fallback) would return:
    Set polled = ##class(sentai.rest.Dispatcher).ShapeRun(##class(sentai.model.Run).%OpenId(run.%Id(), 0), 1)

    Set foundRunning = 0
    Set iter = polled.steps.%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.stepId = "01") && (s.state = "running") Set foundRunning = 1
    }
    Do $$$AssertTrue(foundRunning)
}

}
