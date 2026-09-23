Class sentai.unittest.model.RunTest Extends sentai.unittest.SentaiTestCase
{

Method TestEventVersionStartsAtZeroAndIncrements()
{
    Set id = ..CreateCanonicalFlow("EventVersionFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")
    Do $$$AssertEquals(run.eventVersion, 0)

    Set stepRun = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do stepRun.TransitionTo("running")

    Set refreshed = ##class(sentai.model.Run).%OpenId(run.%Id(), 0)
    Do $$$AssertEquals(refreshed.eventVersion, 1)

    Do stepRun.TransitionTo("completed")
    Set refreshed2 = ##class(sentai.model.Run).%OpenId(run.%Id(), 0)
    Do $$$AssertEquals(refreshed2.eventVersion, 2)
}

}
