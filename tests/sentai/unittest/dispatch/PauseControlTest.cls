Class sentai.unittest.dispatch.PauseControlTest Extends sentai.unittest.SentaiTestCase
{

Method DispatchAndRun(stepId As %String) As %String
{
    Set id = ..CreateCanonicalFlow("PauseFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")
    Set sr = ##class(sentai.model.StepRun).%OpenId(##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), stepId, 0), 4)
    Do sr.TransitionTo("running")
    Quit sr.guid
}

Method TestPausingPurgeFamilyStepTransitionsOnlyThatStep()
{
    Set guid04 = ..DispatchAndRun("04")
    // Find the run guid via the step run.
    Set stepRunId = ##class(sentai.model.StepRun).GuidIndexOpen(guid04, 0)
    Set sr = ##class(sentai.model.StepRun).%OpenId(stepRunId, 0)
    Set run = ##class(sentai.model.Run).%OpenId(sr.run.%Id(), 0)

    Set sc = ##class(sentai.dispatch.WaveDispatcher).PauseStep(run.guid, guid04)
    Do $$$AssertStatusOK(sc)

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(stepRunId, 0)
    Do $$$AssertEquals(refreshed.state, "paused")
}

Method TestPausingNonPurgeTypeIsExplicitlyRefused()
{
    Set guid01 = ..DispatchAndRun("01")
    Set stepRunId = ##class(sentai.model.StepRun).GuidIndexOpen(guid01, 0)
    Set sr = ##class(sentai.model.StepRun).%OpenId(stepRunId, 0)
    Set run = ##class(sentai.model.Run).%OpenId(sr.run.%Id(), 0)

    Set sc = ##class(sentai.dispatch.WaveDispatcher).PauseStep(run.guid, guid01)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "SentaiNotPausable")

    Set refreshed = ##class(sentai.model.StepRun).%OpenId(stepRunId, 0)
    Do $$$AssertEquals(refreshed.state, "running")
}

}
