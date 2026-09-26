/// Spec 005 T006/T007/T013: a declared (in-process) step inside a run — detached on a WQM
/// worker, ended by the worker or by the loop's timeout sweep, streamed like any transition.
Class sentai.unittest.dispatch.DeclaredStepRunTest Extends sentai.unittest.SentaiTestCase
{

/// Waits up to `seconds` for the StepRun to leave `running`/`queued`; returns it fresh.
ClassMethod AwaitTerminal(guid As %String, seconds As %Integer = 10) As sentai.model.StepRun
{
    For i = 1:1:(seconds * 10) {
        Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
        Do sr.%Reload()
        Quit:$LISTFIND($LB("completed", "failed", "cancelled"), sr.state)
        Hang 0.1
    }
    Quit sr
}

Method MixedRun(prefix As %String) As sentai.model.Run
{
    Set flowId = ..CreateFlowOf(prefix, [{"id": "01", "type": "db-size-report"}, {"id": "02", "type": "integrity-check"}], [{"source": "01", "target": "02"}])
    Quit ..DispatchUngated(flowId)
}

/// (a) + (c): 01 runs on a worker, ends completed with its runner, 02 becomes eligible, and the
/// worker's transitions bump the run's eventVersion (what the event stream watches).
Method TestMixedFlowRunsTheDeclaredStepOnAWorker()
{
    Set run = ..MixedRun("DeclaredMixed")
    Set before = run.eventVersion
    Set guid = ^sentaiRun(run.guid, "01")

    Set started = $ZH
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01"))
    Do $$$AssertTrue(($ZH - started) < 2, "StartStep does not wait for the work")

    Set sr = ..AwaitTerminal(guid)
    Do $$$AssertEquals(sr.state, "completed", sr.failureReason)
    Do $$$AssertEquals(sr.executedAs, $USERNAME)
    Do $$$AssertEquals(sr.adminJobId, "", "no management-API job")
    Set result = ##class(%DynamicObject).%FromJSON(sr.result)
    Do $$$AssertTrue(result.databases.%Size() > 0)

    Kill eligible
    Do ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)
    Do $$$AssertEquals($G(eligible(1)), "02")

    Do run.%Reload()
    Do $$$AssertTrue(run.eventVersion >= (before + 2), "running + completed streamed: "_before_" -> "_run.eventVersion)
}

Method SetRunningSince(guid As %String, minutesAgo As %Integer)
{
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "running"))
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
    Do sr.%Reload()
    Set h = $H, secs = $P(h, ",", 2) - (minutesAgo * 60), day = +h
    While (secs < 0) { Set secs = secs + 86400, day = day - 1 }
    Set sr.timeStarted = $ZDATETIME(day_","_secs, 3)
    Do $$$AssertStatusOK(sr.%Save())
}

/// (b): the timeout counts from `running` (so it includes waiting for a worker).
Method TestTimeoutSweepFailsAnOverdueStep()
{
    Set flowId = ..CreateFlowOf("DeclaredTimeout", [{"id": "01", "type": "db-size-report", "timeoutMinutes": 1}, {"id": "02", "type": "db-size-report", "timeoutMinutes": 0}, {"id": "03", "type": "db-size-report", "timeoutMinutes": 0}])
    Set run = ..DispatchUngated(flowId)
    Do ..SetRunningSince(^sentaiRun(run.guid, "01"), 2)
    Do ..SetRunningSince(^sentaiRun(run.guid, "02"), 61)
    Do ..SetRunningSince(^sentaiRun(run.guid, "03"), 30)

    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).SweepTimeouts(run))

    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(^sentaiRun(run.guid, "01"), 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "failed")
    Do $$$AssertEquals(sr.failureReason, "timed out after 1 min")
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(^sentaiRun(run.guid, "02"), 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.failureReason, "timed out after 60 min", "timeoutMinutes 0 means 60")
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(^sentaiRun(run.guid, "03"), 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "running", "within the default 60 min")
}

/// A management-API step is never timed out by the sweep (its job is polled instead).
Method TestTimeoutSweepIgnoresPlatformApiSteps()
{
    Set flowId = ..CreateFlowOf("DeclaredTimeoutIC", [{"id": "01", "type": "integrity-check", "timeoutMinutes": 1}])
    Set run = ..DispatchUngated(flowId)
    Do ..SetRunningSince(^sentaiRun(run.guid, "01"), 5)
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).SweepTimeouts(run))
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(^sentaiRun(run.guid, "01"), 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "running")
}

/// (d): a failed in-process step re-run while the run is live is queued and executed again.
Method TestRerunOfAFailedDeclaredStepRunsAgain()
{
    Set run = ..MixedRun("DeclaredRerun")
    Set old = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(old, "running"))
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(old, "failed", "first attempt failed"))

    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, old, .newGuid))
    Do $$$AssertTrue(newGuid '= old)
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01"))
    Set sr = ..AwaitTerminal(newGuid)
    Do $$$AssertEquals(sr.state, "completed", sr.failureReason)
}

/// An unknown WQM category fails the step with the platform's text, as for integrity checks.
Method TestUnknownCategoryFailsTheStep()
{
    Set flowId = ..CreateFlowOf("DeclaredNoCategory", [{"id": "01", "type": "db-size-report", "wqmCategory": "NO.SUCH.CATEGORY"}])
    Set run = ..DispatchUngated(flowId)
    Do ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(^sentaiRun(run.guid, "01"), 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "failed")
    Do $$$AssertTrue(sr.failureReason '= "")
}

/// T007: the run read shows the declared step's result and runner; other steps show {} and "".
Method TestRunReadShowsResultAndExecutedAs()
{
    Set run = ..MixedRun("DeclaredRead")
    Set guid = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01"))
    Do ..AwaitTerminal(guid)

    Set shaped = ##class(sentai.rest.Dispatcher).ShapeRun(run, 1)
    Set iter = shaped.steps.%GetIterator()
    While iter.%GetNext(.k, .step) {
        Do $$$AssertEquals(step.%GetTypeOf("result"), "object", step.stepId)
        If (step.stepId = "01") {
            Do $$$AssertEquals(step.state, "completed", step.failureReason)
            Do $$$AssertEquals(step.executedAs, $USERNAME)
            Do $$$AssertTrue(step.result.databases.%Size() > 0)
        } Else {
            Do $$$AssertEquals(step.executedAs, "")
            Do $$$AssertEquals(step.result.%ToJSON(), "{}")
        }
    }
}

/// T013: purge-task-history is destructive — a typed confirmation is required before dispatch,
/// and it is neither schedulable as destructive nor as in-process.
Method TestPurgeTaskHistoryNeedsConfirmationAndIsNotSchedulable()
{
    Set id = ..CreateFlowOf("DeclaredPurgeTH", [{"id": "01", "type": "purge-task-history", "namespace": "%SYS", "parameters": {"keepDays": 30}}])
    Do $$$AssertNotTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, [], .pending))
    Do $$$AssertEquals(pending, "01")
    Do $$$AssertTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, [{"stepId": "01", "typedName": "%SYS"}], .pending))

    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Set codes = ""
    Set iter = report.errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Set codes = codes_","_e.code
    }
    Do $$$AssertTrue(codes [ ",DESTRUCTIVE_NOT_SCHEDULABLE", codes)
    Do $$$AssertTrue(codes [ ",IN_PROCESS_NOT_SCHEDULABLE", codes)
}

/// T013: the schema is applied to the native class — KeepDays gets the step's value or 30.
Method TestPurgeTaskHistoryKeepDaysReachesTheTask()
{
    Set schema = ##class(sentai.registry.StepType).GetParameterSchema("purge-task-history")
    Set task = ##class(%SYS.Task.PurgeTaskHistory).%New()
    Do ##class(sentai.dispatch.InProcessExecutor).ApplyParameters(task, schema, {"keepDays": 45})
    Do $$$AssertEquals(task.KeepDays, 45)
    Set task = ##class(%SYS.Task.PurgeTaskHistory).%New()
    Do ##class(sentai.dispatch.InProcessExecutor).ApplyParameters(task, schema, {})
    Do $$$AssertEquals(task.KeepDays, 30)
}

}
