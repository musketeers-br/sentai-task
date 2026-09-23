Class sentai.unittest.dispatch.RerunControlTest Extends sentai.unittest.SentaiTestCase
{

Method TestRerunningFailedStepCreatesNewGuidStartingQueued()
{
    Set id = ..CreateCanonicalFlow("RerunFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set oldGuid = sr01.guid
    Do sr01.TransitionTo("running")
    Do sr01.TransitionTo("failed", "simulated failure")

    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, oldGuid, .newGuid)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertNotEquals(newGuid, oldGuid)

    Set newSr = ##class(sentai.model.StepRun).GuidIndexOpen(newGuid, 0)
    Do $$$AssertEquals(newSr.state, "queued")
    Do $$$AssertEquals(newSr.stepId, "01")

    // The other steps are unaffected.
    Set sr02 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "02", 0)
    Do $$$AssertEquals(sr02.state, "queued")
}

Method TestRerunningNonFailedStepIsRejected()
{
    Set id = ..CreateCanonicalFlow("RerunNonFailed")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .report)

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 0)
    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, sr01.guid, .newGuid)
    Do $$$AssertStatusNotOK(sc)
}

}
