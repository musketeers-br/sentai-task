Class sentai.unittest.dispatch.PauseControlTest Extends sentai.unittest.SentaiTestCase
{

Method DispatchAndRun(stepId As %String) As %String
{
    Set id = ..CreateCanonicalFlow("PauseFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), stepId, 4)
    Do sr.TransitionTo("running")
    Quit sr.guid
}

Method TestPausingPurgeFamilyStepTransitionsOnlyThatStep()
{
    Set guid04 = ..DispatchAndRun("04")
    // Find the run guid via the step run.
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid04, 0)
    Set run = ##class(sentai.model.Run).%OpenId(sr.run.%Id(), 0)

    Set sc = ##class(sentai.dispatch.WaveDispatcher).PauseStep(run.guid, guid04)
    Do $$$AssertStatusOK(sc)

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(refreshed.state, "paused")
}

Method TestPauseIsForwardedToTheValidatedAsyncResultEndpoint()
{
    Set guid04 = ..DispatchAndRun("04")
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid04, 4)
    Set sr.adminJobId = "/api/admin/v1/async-result?id=job04"
    Do sr.%Save()
    Set run = sr.run

    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).PauseStep(run.guid, guid04))

    // spec 001 evidence/08a-async-result-pause.json: POST /api/admin/v2/async-result/pause?id=<id>
    Set posted = $G(^sentaiTestDouble("posted", "/api/admin/v2/async-result/pause"))
    Do $$$AssertEquals($LG(posted, 1), "/api/admin/v2/async-result/pause?id=job04")
}

Method TestPausingNonPurgeTypeIsExplicitlyRefused()
{
    Set guid01 = ..DispatchAndRun("01")
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid01, 0)
    Set run = ##class(sentai.model.Run).%OpenId(sr.run.%Id(), 0)

    Set sc = ##class(sentai.dispatch.WaveDispatcher).PauseStep(run.guid, guid01)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "SentaiNotPausable")

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(sr.%Id(), 0)
    Do $$$AssertEquals(refreshed.state, "running")
}

}
