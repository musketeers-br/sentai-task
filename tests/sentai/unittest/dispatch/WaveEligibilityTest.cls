Class sentai.unittest.dispatch.WaveEligibilityTest Extends sentai.unittest.SentaiTestCase
{

Method DispatchCanonical() As sentai.model.Run
{
    Set id = ..CreateCanonicalFlow("EligibilityFixture")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")
    Quit run
}

Method StepRunFor(run As sentai.model.Run, stepId As %String) As sentai.model.StepRun
{
    Quit ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), stepId, 4)
}

Method TestRootStepsAreImmediatelyEligible()
{
    Set run = ..DispatchCanonical()
    Set n = ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)
    // Steps 01, 02, 03 have no incoming edges — all three are eligible in the first wave.
    Do $$$AssertEquals(n, 3)
}

Method TestFanInTargetIneligibleUntilAllThreeSourcesComplete()
{
    Set run = ..DispatchCanonical()

    Do ..StepRunFor(run, "01").TransitionTo("running")
    Do ..StepRunFor(run, "02").TransitionTo("running")
    Do ..StepRunFor(run, "03").TransitionTo("running")
    Do ..StepRunFor(run, "01").TransitionTo("completed")
    Do ..StepRunFor(run, "02").TransitionTo("completed")

    Set n = ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)
    Set foundStep04 = 0
    Set i = ""
    For {
        Set i = $O(eligible(i))
        Quit:i=""
        If (eligible(i) = "04") Set foundStep04 = 1
    }
    Do $$$AssertNotTrue(foundStep04)

    Do ..StepRunFor(run, "03").TransitionTo("completed")
    Kill eligible2
    Set n2 = ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed2, .eligible2)
    Set foundStep04Now = 0
    Set j = ""
    For {
        Set j = $O(eligible2(j))
        Quit:j=""
        If (eligible2(j) = "04") Set foundStep04Now = 1
    }
    Do $$$AssertTrue(foundStep04Now)
}

}
