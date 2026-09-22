Class sentai.unittest.model.StepRunTest Extends sentai.unittest.SentaiTestCase
{

Method NewQueuedStepRun() As sentai.model.StepRun
{
    Set id = ..CreateCanonicalFlow("StepRunFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")

    Set stepRunId = ##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), "01", 0)
    Quit ##class(sentai.model.StepRun).%OpenId(stepRunId, 4)
}

Method TestCompletedIsTerminal()
{
    Set sr = ..NewQueuedStepRun()
    Do sr.TransitionTo("running")
    Do sr.TransitionTo("completed")
    Set sc = sr.TransitionTo("running")
    Do $$$AssertStatusNotOK(sc)
}

Method TestFailedIsTerminal()
{
    Set sr = ..NewQueuedStepRun()
    Do sr.TransitionTo("running")
    Do sr.TransitionTo("failed")
    Set sc = sr.TransitionTo("queued")
    Do $$$AssertStatusNotOK(sc)
}

Method TestCancelledIsTerminal()
{
    Set sr = ..NewQueuedStepRun()
    Do sr.TransitionTo("cancelled")
    Set sc = sr.TransitionTo("running")
    Do $$$AssertStatusNotOK(sc)
}

Method TestQueuedToPausedIsForbidden()
{
    Set sr = ..NewQueuedStepRun()
    Set sc = sr.TransitionTo("paused")
    Do $$$AssertStatusNotOK(sc)
}

Method TestQueuedToRunningIsLegal()
{
    Set sr = ..NewQueuedStepRun()
    Set sc = sr.TransitionTo("running")
    Do $$$AssertStatusOK(sc)
    Do $$$AssertEquals(sr.state, "running")
}

}
