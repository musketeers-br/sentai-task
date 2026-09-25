Class sentai.unittest.model.StepRunTest Extends sentai.unittest.SentaiTestCase
{

Method NewQueuedStepRun() As sentai.model.StepRun
{
    Set id = ..CreateCanonicalFlow("StepRunFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")

    Quit ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
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
