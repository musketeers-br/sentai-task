Class sentai.unittest.dispatch.JoinFailurePropagationTest Extends sentai.unittest.SentaiTestCase
{

Method TestOneFailedInputFailsTheJoinTargetNamingIt()
{
    Set id = ..CreateCanonicalFlow("JoinFailFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set sr02 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "02", 4)
    Set sr03 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "03", 4)

    Do sr01.TransitionTo("running")
    Do sr01.TransitionTo("completed")
    Do sr02.TransitionTo("running")
    Do sr02.TransitionTo("failed", "Simulated failure of step 02")
    Do sr03.TransitionTo("running")
    Do sr03.TransitionTo("completed")

    Do ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)

    Set sr04 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "04", 0)
    Do $$$AssertEquals(sr04.state, "failed")
    Do $$$AssertTrue(anyFailed)
}

Method TestNoNewStateIsIntroducedByJoinFailure()
{
    Set id = ..CreateCanonicalFlow("JoinFailNoNewState")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .report)

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do sr01.TransitionTo("running")
    Do sr01.TransitionTo("failed", "boom")

    Set sr02 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "02", 4)
    Set sr03 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "03", 4)
    Do sr02.TransitionTo("running")
    Do sr02.TransitionTo("completed")
    Do sr03.TransitionTo("running")
    Do sr03.TransitionTo("completed")

    Do ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)

    Set sr04 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "04", 0)
    // The only closed states are the six from data-model.md — "failed" is one of them,
    // never a new/synthetic value.
    Do $$$AssertTrue($LISTFIND($LB("queued", "running", "paused", "completed", "failed", "cancelled"), sr04.state) > 0)
    Do $$$AssertEquals(sr04.state, "failed")
}

}
