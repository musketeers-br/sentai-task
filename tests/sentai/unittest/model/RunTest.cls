Class sentai.unittest.model.RunTest Extends sentai.unittest.SentaiTestCase
{

Method TestEventVersionStartsAtZeroAndIncrements()
{
    Set id = ..CreateCanonicalFlow("EventVersionFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")
    Do $$$AssertEquals(run.eventVersion, 0)

    Set stepRunId = ##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), "01", 0)
    Set stepRun = ##class(sentai.model.StepRun).%OpenId(stepRunId, 4)
    Do stepRun.TransitionTo("running")

    Set refreshed = ##class(sentai.model.Run).%OpenId(run.%Id(), 0)
    Do $$$AssertEquals(refreshed.eventVersion, 1)

    Do stepRun.TransitionTo("completed")
    Set refreshed2 = ##class(sentai.model.Run).%OpenId(run.%Id(), 0)
    Do $$$AssertEquals(refreshed2.eventVersion, 2)
}

}
