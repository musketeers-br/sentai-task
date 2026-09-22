Class sentai.unittest.dispatch.CancelControlTest Extends sentai.unittest.SentaiTestCase
{

Method DispatchCanonical() As sentai.model.Run
{
    Set id = ..CreateCanonicalFlow("CancelFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")
    Quit run
}

Method StepRunFor(run As sentai.model.Run, stepId As %String) As sentai.model.StepRun
{
    Quit ##class(sentai.model.StepRun).%OpenId(##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), stepId, 0), 4)
}

Method TestIndividualCancelAffectsOnlyThatStep()
{
    Set run = ..DispatchCanonical()
    Do ..StepRunFor(run, "01").TransitionTo("running")
    Do ..StepRunFor(run, "02").TransitionTo("running")

    Set sr01 = ..StepRunFor(run, "01")
    Do ##class(sentai.dispatch.WaveDispatcher).CancelStep(run.guid, sr01.guid)

    Set refreshed01 = ##class(sentai.model.StepRun).%OpenId(sr01.%Id(), 0)
    Do $$$AssertEquals(refreshed01.state, "cancelled")

    Set sr02 = ..StepRunFor(run, "02")
    Do $$$AssertEquals(sr02.state, "running")
}

Method TestWholeRunCancelStopsPendingAndCancelsRunning()
{
    Set run = ..DispatchCanonical()
    Do ..StepRunFor(run, "01").TransitionTo("running")
    // 02, 03, 04, 05 remain queued.

    Do ##class(sentai.dispatch.WaveDispatcher).CancelRun(run.guid)

    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT state FROM sentai.model.StepRun WHERE run = ?")
    Set result = rs.%Execute(run.%Id())
    While result.%Next() {
        Do $$$AssertEquals(result.%Get("state"), "cancelled")
    }
}

}
