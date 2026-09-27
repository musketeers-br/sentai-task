/// Spec 008 T008 (US2, FR-012…FR-015, FR-018, research R-10): a step on a target starts its job
/// there with the operator's credential for it, is followed like a local step, keeps its result
/// on the primary and records where it ran. One test double answers for the primary (paths) and
/// one for the target (base URL + path).
Class sentai.unittest.dispatch.RemoteStepRunTest Extends sentai.unittest.SentaiTestCase
{

Parameter BASE = "https://remote.example:52773";

Parameter START = "/api/admin/v2/database-dir/integrity-check";

Property Name As %String;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Set ..Name = ##class(sentai.unittest.targets.TargetServiceTest).Unique("remote")
    Do ##class(sentai.targets.TargetService).Create({"name": (..Name), "baseUrl": (..#BASE)}, "tester")
    // The primary's job and the target's job (t0-target-calls 06: Location is a path).
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#START, "POST", 202, "/api/admin/v1/async-result?id=L1", "{}")
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_..#START, "POST", 202, "/api/admin/v1/async-result?id=R1", "{}")
    Quit sc
}

/// The demo shape: 01 and 02 local, 03 on the target, all three into 04 (local). A run with the
/// local credential and the redeemed target credential in place, as dispatch leaves them.
Method DemoRun() As sentai.model.Run
{
    Set id = ..CreateFlowOf("RemoteRun", [{"id": "01", "type": "integrity-check"}, {"id": "02", "type": "integrity-check"}, {"id": "03", "type": "integrity-check", "namespace": "USER", "target": (..Name)}, {"id": "04", "type": "integrity-check"}], [{"source": "01", "target": "04"}, {"source": "02", "target": "04"}, {"source": "03", "target": "04"}])
    Set run = ..DispatchUngated(id)
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "LOCAL-A")
    Set pairs = {}
    Do pairs.%Set(..Name, {"accessToken": "TGT-A", "refreshToken": "TGT-R", "sub": "remote-op", "baseUrl": (..#BASE)})
    Do ##class(sentai.dispatch.WaveDispatcher).StoreTargetCredentials(run.guid, pairs)
    Quit run
}

ClassMethod StepRun(run As sentai.model.Run, stepId As %String) As sentai.model.StepRun
{
    Quit ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), stepId, 0)
}

/// The bearer each POST to `url` carried (postlog), in order.
ClassMethod BearersPostedTo(url As %String) As %String
{
    Set out = "", n = ""
    For {
        Set n = $O(^sentaiTestDouble("postlog", n), 1, entry)
        Quit:(n = "")
        Set:($LG(entry, 1) = url) out = out_$LG(entry, 3)_","
    }
    Quit out
}

Method TestPlacementIsKnownFromTheStart()
{
    Set run = ..DemoRun()
    Do $$$AssertEquals(..StepRun(run, "01").executedOn, "local")
    Do $$$AssertEquals(..StepRun(run, "03").executedOn, ..Name)
    Set shaped = ##class(sentai.rest.Dispatcher).ShapeStepRun(..StepRun(run, "03"))
    Do $$$AssertEquals(shaped.executedOn, ..Name)
}

Method TestRemoteStepStartsOnTheTargetWithItsCredential()
{
    Set run = ..DemoRun()
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01"))
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03"))

    Set local = ..StepRun(run, "01"), remote = ..StepRun(run, "03")
    Do $$$AssertEquals(local.state, "running")
    Do $$$AssertEquals(local.targetBaseUrl, "")
    Do $$$AssertEquals(local.adminJobId, "/api/admin/v1/async-result?id=L1")
    Do $$$AssertEquals(..BearersPostedTo(..#START), "LOCAL-A,")

    Do $$$AssertEquals(remote.state, "running")
    Do $$$AssertEquals(remote.targetBaseUrl, ..#BASE)
    Do $$$AssertEquals(remote.adminJobId, "/api/admin/v1/async-result?id=R1")
    Do $$$AssertEquals(remote.executedAs, "remote-op", "the target credential's user")
    Do $$$AssertEquals(..BearersPostedTo(..#BASE_..#START), "TGT-A,")
}

Method TestResultsAreKeptOnThePrimaryForLocalAndRemoteSteps()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Set remoteResult = {"State": "Finished", "TaskName": "POST /v2/database-dir/integrity-check", "Console": ["No Errors were found."]}
    Set localResult = {"State": "Finished", "TaskName": "POST /v2/database-dir/integrity-check", "Console": ["local report"]}
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/v1/async-result?id=R1", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": (remoteResult)}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v1/async-result?id=L1", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": (localResult)}.%ToJSON())

    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")

    Set remote = ..StepRun(run, "03"), local = ..StepRun(run, "01")
    Do $$$AssertEquals(remote.state, "completed")
    Do $$$AssertEquals(remote.result, remoteResult.%ToJSON())
    Do $$$AssertEquals(local.state, "completed")
    Do $$$AssertEquals(local.result, localResult.%ToJSON(), "R-10: platform steps keep their result too")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#BASE_"/api/admin/v1/async-result?id=R1")), "TGT-A")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", "/api/admin/v1/async-result?id=L1")), "LOCAL-A")
}

Method TestTargetFailureIsTheStepsReasonVerbatim()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/v1/async-result?id=R1", "GET", 200, "", {"status": {"errors": [], "summary": "ERROR #5001: Integrity check failed on /usr/irissys/mgr/user/"}, "result": {"State": "Error"}}.%ToJSON())
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")
    Do $$$AssertEquals(..StepRun(run, "03").state, "failed")
    Do $$$AssertEquals(..StepRun(run, "03").failureReason, "ERROR #5001: Integrity check failed on /usr/irissys/mgr/user/")
}

Method TestTargetThatDoesNotAnswerAtStartFailsTheStep()
{
    Set run = ..DemoRun()
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: Unable to open TCP/IP socket to server remote.example:52773")
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do $$$AssertEquals(..StepRun(run, "03").state, "failed")
    Do $$$AssertEquals(..StepRun(run, "03").failureReason, "Target '"_..Name_"' did not answer: ERROR #6059: Unable to open TCP/IP socket to server remote.example:52773")
}

/// FR-018: an address edited after the run started does not move a started step.
Method TestAddressIsFrozenForTheRun()
{
    Set run = ..DemoRun()
    Do ##class(sentai.targets.TargetService).Update(..Name, {"baseUrl": "https://elsewhere.example:52773"}, "tester")
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do $$$AssertEquals(..StepRun(run, "03").targetBaseUrl, ..#BASE)
    Do $$$AssertEquals(..BearersPostedTo(..#BASE_..#START), "TGT-A,")
}

/// T009 (FR-017): cancelling a running remote step asks its target first, with the run's
/// credential for it; the step is cancelled once the target accepted.
Method TestCancelIsForwardedToTheTarget()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Set sr = ..StepRun(run, "03")
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).CancelStep(run.guid, sr.guid))
    Do $$$AssertEquals(..StepRun(run, "03").state, "cancelled")
    Do $$$AssertEquals(..BearersPostedTo(..#BASE_"/api/admin/v2/async-result/cancel?id=R1"), "TGT-A,")
}

/// A refusal from the target leaves the step as it is and comes back verbatim.
Method TestRefusedCancelLeavesTheStepRunning()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/v2/async-result/cancel", "POST", 403, "", {"status": {"errors": [{"error": "ERROR #822: Access Denied"}], "summary": "ERROR #822: Access Denied"}}.%ToJSON())
    Set sc = ##class(sentai.dispatch.WaveDispatcher).CancelStep(run.guid, ..StepRun(run, "03").guid)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "CONTROL_REFUSED: target '"_..Name_"' answered HTTP 403: ERROR #822: Access Denied", $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(..StepRun(run, "03").state, "running")

    // Over the route: 502 with that text.
    Do ##class(sentai.unittest.targets.TargetRestTest).Request()
    Do ##class(sentai.rest.Dispatcher).CancelStep(run.guid, ..StepRun(run, "03").guid)
    Do $$$AssertEquals(%response.Status, 502)
}

/// A local running platform step is now cancelled on the platform too (spec 003 F-2 / T075).
Method TestLocalCancelIsForwardedToo()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).CancelStep(run.guid, ..StepRun(run, "01").guid))
    Do $$$AssertEquals(..StepRun(run, "01").state, "cancelled")
    Do $$$AssertEquals(..BearersPostedTo("/api/admin/v2/async-result/cancel?id=L1"), "LOCAL-A,")
}

/// Cancelling the whole run forwards to every running job, on its own instance.
Method TestRunCancelForwardsToEachJob()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do ##class(sentai.dispatch.WaveDispatcher).CancelRun(run.guid)
    Do $$$AssertEquals(..BearersPostedTo(..#BASE_"/api/admin/v2/async-result/cancel?id=R1"), "TGT-A,")
    Do $$$AssertEquals(..BearersPostedTo("/api/admin/v2/async-result/cancel?id=L1"), "LOCAL-A,")
    Do $$$AssertEquals(..StepRun(run, "03").state, "cancelled")
    Do $$$AssertEquals(..StepRun(run, "04").state, "cancelled")
}

/// T010 (FR-016, research R-12): a target that stops answering mid-run keeps its step running
/// while the step's timeout lasts, then fails only that step with the last transport error.
Method TestTargetDownMidRunFailsOnlyItsStepAfterTheTimeout()
{
    Set id = ..CreateFlowOf("RemoteDown", [{"id": "01", "type": "integrity-check"}, {"id": "03", "type": "integrity-check", "namespace": "USER", "target": (..Name), "timeoutMinutes": 1}])
    Set run = ..DispatchUngated(id)
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "LOCAL-A")
    Set pairs = {}
    Do pairs.%Set(..Name, {"accessToken": "TGT-A", "refreshToken": "TGT-R", "sub": "remote-op", "baseUrl": (..#BASE)})
    Do ##class(sentai.dispatch.WaveDispatcher).StoreTargetCredentials(run.guid, pairs)
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")

    Set text = "ERROR #6059: Unable to open TCP/IP socket to server remote.example:52773"
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, text)
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")
    Do ##class(sentai.dispatch.WaveDispatcher).SweepTimeouts(run)
    Do $$$AssertEquals(..StepRun(run, "03").state, "running", "within its timeout")

    // Past the timeout.
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "03", 4)
    Set sr.timeStarted = $ZDATETIME($SYSTEM.SQL.Functions.DATEADD("mi", -2, $ZDATETIME($HOROLOG, 3)), 3)
    Do sr.%Save()
    Do ##class(sentai.dispatch.WaveDispatcher).SweepTimeouts(run)
    Do $$$AssertEquals(..StepRun(run, "03").state, "failed")
    Do $$$AssertEquals(..StepRun(run, "03").failureReason, "timed out after 1 min; last transport error: "_text)
    Do $$$AssertEquals(..StepRun(run, "01").state, "running", "the local step is untouched")
}

/// A 4xx from the target stays permanent, as for local steps, with its text.
Method TestTargetRefusalWhilePollingIsPermanent()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/v1/async-result?id=R1", "GET", 401, "", {"status": {"errors": [], "summary": "ERROR #822: Access Denied"}}.%ToJSON())
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")
    Do $$$AssertEquals(..StepRun(run, "03").state, "failed")
    Do $$$AssertTrue(..StepRun(run, "03").failureReason [ "HTTP 401: ERROR #822: Access Denied", ..StepRun(run, "03").failureReason)
}

/// Quickstart (e) finding: a target that does not answer must not hold the run. After a transport
/// failure the loop leaves that target alone for a while (polls and renewals), so local steps and
/// the timeout sweep keep their pace.
Method TestADownTargetIsLeftAloneForAWhile()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "03")
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: Unable to open TCP/IP socket to server remote.example:52773")
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")
    Set $LIST(^IRIS.Temp.sentaiTargetCred(run.guid, ..Name), 3) = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 41
    Do ##class(sentai.dispatch.WaveDispatcher).RenewTargetCredentialsIfDue(run.guid)
    Do $$$AssertEquals(^sentaiTestDouble("downcalls", ..#BASE), 1, "one call, then back-off")

    // Once the back-off has passed, the target is tried again.
    Set ^IRIS.Temp.sentaiTargetCred(run.guid, "%failAt", ..Name) = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 31
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-A")
    Do $$$AssertEquals(^sentaiTestDouble("downcalls", ..#BASE), 2)
}

/// Quickstart (e) finding: the local run credential is renewed right before a local poll, so a
/// slow pass can never let it expire under a running local step.
Method TestLocalCredentialIsRenewedBeforeALocalPoll()
{
    Set run = ..DemoRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "LOCAL-OLD", "LOCAL-REF")
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Set ^sentaiRun(run.guid, "%tokenAt") = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 50
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/refresh", "POST", 200, "", {"access_token": "LOCAL-NEW", "refresh_token": "LOCAL-REF2"}.%ToJSON())
    Do ##class(sentai.dispatch.WaveDispatcher).PollInFlightSteps(run, "LOCAL-OLD")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", "/api/admin/v1/async-result?id=L1")), "LOCAL-NEW")
}

}
