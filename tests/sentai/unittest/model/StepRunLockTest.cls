/// Spec 005 T003 (plan item 3): terminal transitions written by a worker and by the run loop's
/// timeout sweep go through StepRun.TransitionLocked — exclusive lock + fresh read — so exactly
/// one terminal state wins and the loser is refused, never silently overwritten.
Class sentai.unittest.model.StepRunLockTest Extends sentai.unittest.SentaiTestCase
{

/// Runs in a JOB child: waits for the parent's go signal, then races it.
ClassMethod RaceChild(key As %String, guid As %String, newState As %String)
{
    For i = 1:1:200 { Quit:$G(^sentaiTestLock(key, "go"))  Hang 0.01 }
    Set sc = ##class(sentai.model.StepRun).TransitionLocked(guid, newState)
    Set ^sentaiTestLock(key, "child") = $S($$$ISOK(sc):"OK", 1:$SYSTEM.Status.GetErrorText(sc))
}

Method RunningStepRunGuid(prefix As %String) As %String
{
    Set run = ..DispatchUngated(..CreateSupportedFlow(prefix))
    Set guid = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "running"))
    Quit guid
}

Method TestRunningToCompleted()
{
    Set guid = ..RunningStepRunGuid("LockCompleted")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "completed"))
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
    Do $$$AssertEquals(sr.state, "completed")
    Do $$$AssertTrue(sr.timeFinished '= "")
}

Method TestTwoProcessRaceHasOneWinner()
{
    Set guid = ..RunningStepRunGuid("LockRace")
    Set key = $JOB_"-"_$I(^sentaiTestSeq)
    Kill ^sentaiTestLock(key)
    JOB ..RaceChild(key, guid, "completed")
    Set ^sentaiTestLock(key, "go") = 1
    Set sc = ##class(sentai.model.StepRun).TransitionLocked(guid, "failed", "timed out after 1 min")
    For i = 1:1:500 { Quit:$D(^sentaiTestLock(key, "child"))  Hang 0.02 }
    Set child = $G(^sentaiTestLock(key, "child"), "child never finished")
    Set parent = $S($$$ISOK(sc):"OK", 1:$SYSTEM.Status.GetErrorText(sc))
    Kill ^sentaiTestLock(key)

    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
    Do sr.%Reload()
    Do $$$AssertTrue($LISTFIND($LB("completed", "failed"), sr.state), "terminal: "_sr.state)
    Do $$$AssertEquals((child = "OK") + (parent = "OK"), 1, "exactly one winner: child="_child_" parent="_parent)
    Set loser = $S(child = "OK":parent, 1:child)
    Do $$$AssertTrue(loser [ "SentaiIllegalTransition", "loser refused: "_loser)
    Do $$$AssertEquals(sr.state, $S(child = "OK":"completed", 1:"failed"), "the winner's state is persisted")
}

Method TestStaleObjectCannotOverwrite()
{
    Set guid = ..RunningStepRunGuid("LockStale")
    // This process holds a copy read while the step was running…
    Set stale = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
    Do $$$AssertEquals(stale.state, "running")
    // …another process writes the terminal state…
    Set key = $JOB_"-"_$I(^sentaiTestSeq)
    Set ^sentaiTestLock(key, "go") = 1
    JOB ..RaceChild(key, guid, "failed")
    For i = 1:1:500 { Quit:$D(^sentaiTestLock(key, "child"))  Hang 0.02 }
    Do $$$AssertEquals($G(^sentaiTestLock(key, "child")), "OK")
    Kill ^sentaiTestLock(key)
    // …and a write through TransitionLocked reads fresh and is refused, even with `stale` in memory.
    Do $$$AssertEquals(stale.state, "running", "the in-memory copy is stale")
    Set sc = ##class(sentai.model.StepRun).TransitionLocked(guid, "completed")
    Do $$$AssertTrue($$$ISERR(sc))
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "SentaiIllegalTransition")
    Do stale.%Reload()
    Do $$$AssertEquals(stale.state, "failed")
}

}
