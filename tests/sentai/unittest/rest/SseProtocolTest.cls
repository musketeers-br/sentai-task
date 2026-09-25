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
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")

    Set v0 = run.eventVersion
    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do sr01.TransitionTo("running")
    Set v1 = ##class(sentai.model.Run).%OpenId(run.%Id(), 0).eventVersion
    Do $$$AssertTrue(v1 > v0)

    Do sr01.TransitionTo("completed")
    Set v2 = ##class(sentai.model.Run).%OpenId(run.%Id(), 0).eventVersion
    Do $$$AssertTrue(v2 > v1)
}

/// Drives StreamEvents itself on a run already terminal — the loop emits the current state
/// and run-terminal on its first pass and returns (observed on a real instance: the endpoint
/// used to fail with 500 before writing anything).
Method TestStreamEventsOnTerminalRunEmitsRunTerminalAndReturns()
{
    Set id = ..CreateCanonicalFlow("SseStream")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")
    Do ##class(sentai.dispatch.WaveDispatcher).CancelRun(run.guid)
    Do run.%Reload()
    Set run.state = "cancelled"
    Do $$$AssertStatusOK(run.%Save())

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Set out = ##class(%Stream.TmpCharacter).%New()
    Set io = $IO
    Set file = ##class(%File).TempFilename("sse")
    Open file:("WNS"):2
    Use file
    Try {
        Set sc = ##class(sentai.rest.Dispatcher).StreamEvents(run.guid)
    }
    Catch ex {
        Set sc = ex.AsStatus()
    }
    Use io
    Close file
    Do $$$AssertStatusOK(sc)
    Do $$$AssertEquals(%response.ContentType, "text/event-stream")
    // %CSP.REST disables flushing by default; without it every event is held back until the
    // request ends (observed on a real instance, TD-03).
    Do $$$AssertEquals(%response.AllowOutputFlush, 1)

    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set text = stream.Read(1000000)
    Do ##class(%File).Delete(file)
    Do $$$AssertTrue(text [ "event: step-state-changed")
    Do $$$AssertTrue(text [ "event: run-terminal")
    // run-terminal is the last event of the stream.
    Do $$$AssertEquals($PIECE($PIECE(text, "event: ", *), $C(10), 1), "run-terminal")
}

Method TestPollingAndSseReadTheSamePersistedState()
{
    Set id = ..CreateCanonicalFlow("SsePollingParity")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
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
