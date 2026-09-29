/// Spec 012 US1: the only writer of a run's log. Each method records one fact the product already
/// establishes where it is established (data-model §2), with the platform's words verbatim and
/// whole (Constitution III). A log entry is a record, never a gate: every method returns a
/// %Status and never throws, and callers ignore failures (FR-004).
Class sentai.dispatch.RunNarrator Extends %RegisteredObject
{

/// LogEntry.message holds at most this many characters; longer text is split into ordered parts.
Parameter MAXMESSAGE = 4000;

/// Run dispatched (WaveDispatcher.CreateRun).
ClassMethod Dispatched(runId As %String, dispatchedBy As %String, revision As %Integer, steps As %Integer) As %Status
{
    // Part of the new run itself: no extra eventVersion bump.
    Quit ..Write(runId, "", "info", "Run dispatched by "_dispatchedBy_" (flow revision "_revision_", "_steps_" step"_$S(steps = 1:"", 1:"s")_")", 0)
}

/// Spec 015: the first entry of a run started by a flow's schedule.
ClassMethod ScheduledStart(runId As %String, flowName As %String, runAs As %String, revision As %Integer, steps As %Integer) As %Status
{
    Quit ..Write(runId, "", "info", "Run started by the schedule of flow "_flowName_" as "_runAs_" (flow revision "_revision_", "_steps_" step"_$S(steps = 1:"", 1:"s")_")", 0)
}

/// Spec 015 (data-model §4): the only entry of a scheduled run that could not start.
ClassMethod ScheduledStartFailed(runId As %String, reason As %String) As %Status
{
    Quit ..Write(runId, "", "error", "Scheduled run could not start: "_reason, 0)
}

/// Every state change, from StepRun.TransitionTo (plan D-2).
ClassMethod StepChanged(stepRun As sentai.model.StepRun, from As %String, to As %String) As %Status
{
    Try {
        Set runId = stepRun.runGetObjectId(), id = stepRun.stepId
        // Written inside the transition, which bumps eventVersion itself.
        If (to = "running") && (from = "paused") Return ..Write(runId, id, "info", "#"_id_" resumed", 0)
        If (to = "running") {
            Set name = ..TaskName(stepRun)
            Set where = $S(stepRun.executedOn '= "":stepRun.executedOn, 1:"local")
            Return ..Write(runId, id, "info", "#"_id_$S(name '= "":" "_name, 1:"")_" started on "_where, 0)
        }
        If (to = "paused") Return ..Write(runId, id, "info", "#"_id_" paused", 0)
        If (to = "completed") Return ..Write(runId, id, "info", "#"_id_" completed in "_..Duration(stepRun), 0)
        If (to = "cancelled") Return ..Write(runId, id, "warning", "#"_id_" cancelled", 0)
        If (to = "failed") {
            Set after = $S(stepRun.timeStarted '= "":" after "_..Duration(stepRun), 1:"")
            Set reason = stepRun.failureReason
            Return ..Write(runId, id, "error", "#"_id_" failed"_after_$S(reason '= "":": """_reason_"""", 1:""), 0)
        }
        Return $$$OK
    } Catch ex {
        Return ex.AsStatus()
    }
}

/// A step not started because an input failed (ComputeEligibleSteps, plan D-5).
ClassMethod JoinBlocked(runId As %String, stepId As %String, inputId As %String, inputState As %String) As %Status
{
    // The transition to failed that follows bumps eventVersion.
    Quit ..Write(runId, stepId, "error", "#"_stepId_" not started: input #"_inputId_" "_inputState_" (all inputs must succeed)", 0)
}

/// A re-run attempt saved as queued (WaveDispatcher.RerunStep).
ClassMethod RerunQueued(runId As %String, stepId As %String, attempt As %Integer) As %Status
{
    Quit ..Write(runId, stepId, "info", "#"_stepId_" re-run queued (attempt "_attempt_")")
}

/// An operator's cancel / pause / re-run request and its outcome (REST handlers, plan D-4).
/// `refusal` is the problem detail returned to the operator, verbatim; "" when accepted.
ClassMethod Requested(runGuid As %String, stepId As %String, user As %String, action As %String, refusal As %String = "") As %Status
{
    Set runId = ..RunIdOf(runGuid)
    Quit:(runId = "") $$$OK
    Set what = $S(stepId '= "":"#"_stepId, 1:"the run")
    If (refusal = "") Quit ..Write(runId, stepId, "info", user_" asked to "_action_" "_what)
    Quit ..Write(runId, stepId, "warning", user_" asked to "_action_" "_what_"; refused: """_refusal_"""")
}

/// First failed answer of a target in an outage (WaveDispatcher.MarkTargetFailed, plan D-3).
ClassMethod TargetDown(runGuid As %String, target As %String, transportError As %String) As %Status
{
    Set runId = ..RunIdOf(runGuid)
    Quit:(runId = "") $$$OK
    Quit ..Write(runId, "", "warning", "Target "_target_" did not answer: """_transportError_"""; retrying every "_##class(sentai.dispatch.WaveDispatcher).#TARGETBACKOFFSECONDS_" s")
}

ClassMethod TargetUp(runGuid As %String, target As %String) As %Status
{
    Set runId = ..RunIdOf(runGuid)
    Quit:(runId = "") $$$OK
    Quit ..Write(runId, "", "info", "Target "_target_" answers again")
}

/// The platform refused to renew the run's own credential (RenewRunCredentialIfDue).
ClassMethod RenewalRefused(runGuid As %String, httpStatus As %Integer, summary As %String) As %Status
{
    Set runId = ..RunIdOf(runGuid)
    Quit:(runId = "") $$$OK
    Quit ..Write(runId, "", "warning", "Renewing the run's credential was refused: HTTP "_httpStatus_$S(summary '= "":" """_summary_"""", 1:""))
}

/// The run's end (FinalizeRun): outcome and counts over the latest attempt of each step.
ClassMethod Finished(run As sentai.model.Run) As %Status
{
    Try {
        Set runId = run.%Id(), c = 0, f = 0, x = 0
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT state FROM sentai_model.StepRun WHERE ID IN (SELECT MAX(ID) FROM sentai_model.StepRun WHERE run = ? GROUP BY stepId)", runId)
        While rs.%Next() {
            Set s = rs.%Get("state")
            Set:(s = "completed") c = c + 1
            Set:(s = "failed") f = f + 1
            Set:(s = "cancelled") x = x + 1
        }
        Set severity = $CASE(run.state, "failed":"error", "cancelled":"warning", :"info")
        Set ms = run.TotalDurationMs()
        // FinalizeRun bumps eventVersion right after.
        Return ..Write(runId, "", severity, "Run "_run.state_": "_c_" completed, "_f_" failed, "_x_" cancelled ("_..FormatMs(ms)_")", 0)
    } Catch ex {
        Return ex.AsStatus()
    }
}

/// Appends one fact; text longer than MAXMESSAGE goes in consecutive parts "(1/n) …" so nothing is
/// lost. Never throws.
ClassMethod Write(runId As %String, stepId As %String, severity As %String, message As %String, bump As %Boolean = 1) As %Status
{
    Try {
        Quit:(runId = "")
        Set max = ..#MAXMESSAGE - 12, n = ($L(message) + max - 1) \ max
        If (n <= 1) Return ##class(sentai.model.LogEntry).Append(runId, stepId, severity, message, bump)
        For i = 1:1:n {
            Set sc = ##class(sentai.model.LogEntry).Append(runId, stepId, severity, "("_i_"/"_n_") "_$E(message, (i - 1) * max + 1, i * max), bump)
            Return:$$$ISERR(sc) sc
        }
        Return $$$OK
    } Catch ex {
        Return ex.AsStatus()
    }
    Quit $$$OK
}

ClassMethod RunIdOf(runGuid As %String) As %String
{
    Quit:(runGuid = "") ""
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0)
    Quit $S($IsObject(run):run.%Id(), 1:"")
}

ClassMethod TaskName(stepRun As sentai.model.StepRun) As %String
{
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(stepRun.run.flowGetObjectId(), stepRun.stepId, 0)
    Quit $S($IsObject(step):step.taskName, 1:"")
}

/// Elapsed time of a step, in the canvas's mm:ss form (hours when needed).
ClassMethod Duration(stepRun As sentai.model.StepRun) As %String
{
    Quit:(stepRun.timeStarted = "") "00:00"
    Set end = $S(stepRun.timeFinished '= "":stepRun.timeFinished, 1:$ZDATETIME($HOROLOG, 3))
    Quit ..FormatMs(##class(sentai.model.Run).MillisecondsBetween(stepRun.timeStarted, end))
}

ClassMethod FormatMs(ms As %Integer) As %String
{
    Set s = ms \ 1000
    Set:(s < 0) s = 0
    Set h = s \ 3600, m = (s # 3600) \ 60, sec = s # 60
    Quit $S(h > 0:h_":"_$TR($J(m, 2), " ", "0")_":", 1:$TR($J(m, 2), " ", "0")_":")_$TR($J(sec, 2), " ", "0")
}

}
