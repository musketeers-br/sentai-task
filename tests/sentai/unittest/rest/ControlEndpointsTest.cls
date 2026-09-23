Class sentai.unittest.rest.ControlEndpointsTest Extends sentai.unittest.SentaiTestCase
{

Method DispatchCanonical() As sentai.model.Run
{
    Set id = ..CreateCanonicalFlow("ControlEndpointsFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")
    Quit run
}

Method TestPauseOnNonPausableTypeReturns409AndStepStaysRunning()
{
    Set run = ..DispatchCanonical()
    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do sr01.TransitionTo("running")

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).PauseStep(run.guid, sr01.guid)
    Do $$$AssertEquals(%response.Status, 409)

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(sr01.%Id(), 0)
    Do $$$AssertEquals(refreshed.state, "running")
}

Method TestCancelStepReturns202()
{
    Set run = ..DispatchCanonical()
    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 0)

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).CancelStep(run.guid, sr01.guid)
    Do $$$AssertEquals(%response.Status, 202)
}

Method TestRunCancelReturns202()
{
    Set run = ..DispatchCanonical()
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).CancelRun(run.guid)
    Do $$$AssertEquals(%response.Status, 202)
}

}
