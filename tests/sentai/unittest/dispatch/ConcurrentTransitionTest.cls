/// The background loop keeps its Run open for the whole run while %SYSTEM.WorkMgr workers
/// (other processes) transition StepRuns of that same run. A transition must never be held up
/// — let alone rolled back — by a lock the loop process keeps on the Run (FR-022: terminal
/// states are final; observed on a real instance as a failed step flipping back to queued).
Class sentai.unittest.dispatch.ConcurrentTransitionTest Extends sentai.unittest.SentaiTestCase
{

/// Runs on a worker process.
ClassMethod TransitionByGuid(stepRunGuid As %String, newState As %String) As %Status
{
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(stepRunGuid, 4, .sc)
    If '$IsObject(sr) Quit sc
    Quit sr.TransitionTo(newState)
}

Method TestWorkerTransitionSucceedsWhileLoopProcessHoldsTheRun()
{
    Set id = ..CreateCanonicalFlow("ConcurrentTransition")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")

    // Like RunLoop: this process keeps `run` open and performs a transition of its own.
    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do $$$AssertStatusOK(sr01.TransitionTo("running"))

    // A worker process transitions another step of the same run.
    Set sr02 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "02", 0)
    Set queue = $SYSTEM.WorkMgr.%New(, , "Default")
    Do queue.Queue("##class(sentai.unittest.dispatch.ConcurrentTransitionTest).TransitionByGuid", sr02.guid, "running")
    Set started = $ZH
    Do $$$AssertStatusOK(queue.Sync())
    Do $$$AssertTrue(($ZH - started) < 5)

    Do sr02.%Reload()
    Do $$$AssertEquals(sr02.state, "running")

    // Both transitions counted, and visible through the object this process still holds.
    Do run.%Reload()
    Do $$$AssertEquals(run.eventVersion, 2)
}

}
