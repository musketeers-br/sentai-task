Class sentai.unittest.dispatch.RerunControlTest Extends sentai.unittest.SentaiTestCase
{

Method TestRerunningFailedStepCreatesNewGuidStartingQueued()
{
    Set id = ..CreateCanonicalFlow("RerunFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
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
    Set run = ..DispatchUngated(id)

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 0)
    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, sr01.guid, .newGuid)
    Do $$$AssertStatusNotOK(sc)
}

/// Spec 004 FR-002: a failed step whose type is not available in v1 (step 04,
/// purge-audit-records, of a run created before the rule) is not re-run.
Method TestRerunOfUnavailableStepTypeIsRefused()
{
    Set id = ..CreateCanonicalFlow("RerunUnavailable")
    Set run = ..DispatchUngated(id)
    Set sr04 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "04", 4)
    Do sr04.TransitionTo("running")
    Do sr04.TransitionTo("failed", "simulated failure")

    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, sr04.guid, .newGuid)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "STEP_TYPE_NOT_SUPPORTED_ON_TARGET")

    Set runId = run.%Id(), n = ""
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.StepRun WHERE run = :runId AND stepId = '04')
    Do $$$AssertEquals(n, 1)
}

}
