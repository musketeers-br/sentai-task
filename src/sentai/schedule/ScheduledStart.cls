/// Spec 015 (plan D-3, D-5): what a flow's native task does when it fires. It runs in the task's
/// process, as the schedule's run-as account. It signs in on the primary and on every target the
/// schedule covers with the stored wallet secrets (the platform applies them; the password is
/// never read here), then dispatches the flow exactly as a manual run is dispatched, marked
/// `scheduled`. When it cannot start, the attempt is recorded as a failed run with one log entry
/// (data-model §4), and the task gets an error status so the platform's task history shows it.
Class sentai.schedule.ScheduledStart Extends %RegisteredObject
{

ClassMethod Fire(flowId As %String) As %Status
{
    Set schedule = ##class(sentai.model.Schedule).FlowIndexOpen(flowId, 0)
    Quit:'$IsObject(schedule) $$$ERROR($$$GeneralError, "SentaiTask: flow "_flowId_" has no schedule; this task is left over and can be deleted")
    Set runAs = schedule.runAs, generation = schedule.generation

    // The primary sign-in: its pair is the run's credential (E-1), renewed by the run loop.
    Set pair = ..SignIn("", ##class(sentai.schedule.Wallet).SecretName(flowId, generation, "primary"), "primary", .reason)
    Quit:'$IsObject(pair) ..StartFailed(flowId, runAs, reason)

    // One pair per target. A target that does not answer is left without a credential: the run
    // starts and its steps there fail as in any run (spec 008); a refusal stops the start.
    Set targetPairs = {}
    For i = 1:1:$L(schedule.targets, ",") {
        Set name = $P(schedule.targets, ",", i)
        Continue:(name = "")
        Set target = ##class(sentai.targets.TargetService).Open(name)
        Continue:'$IsObject(target)
        Continue:'target.online
        Set targetPair = ..SignIn(target.baseUrl, ##class(sentai.schedule.Wallet).SecretName(flowId, generation, name), name, .reason, .unreachable)
        If $IsObject(targetPair) {
            Do targetPairs.%Set(name, {"accessToken": (targetPair."access_token"), "refreshToken": (targetPair."refresh_token"), "sub": (targetPair.sub), "baseUrl": (target.baseUrl)})
        } ElseIf 'unreachable {
            Quit
        }
        Set reason = ""
    }
    Quit:(reason '= "") ..StartFailed(flowId, runAs, reason)

    Set access = pair."access_token"
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(flowId, [], runAs, .errorCode, .errorDetail, .report, access, ##class(sentai.dispatch.WaveDispatcher).AccessTokens(targetPairs), "scheduled")
    If (run = "") {
        If (errorCode = "VALIDATION_FAILED") {
            Set reason = "the flow does not validate: "_..ReportText(report)
        } ElseIf (errorCode = "CONFIRMATION_REQUIRED") {
            Set reason = "step '"_errorDetail_"' is destructive and needs a typed confirmation, which a scheduled run cannot give"
        } Else {
            Set reason = errorCode_" "_errorDetail
        }
        Quit ..StartFailed(flowId, runAs, reason)
    }
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, access, pair."refresh_token")
    Do ##class(sentai.dispatch.WaveDispatcher).StoreTargetCredentials(run.guid, targetPairs)
    Do ##class(sentai.dispatch.WaveDispatcher).StartBackgroundLoop(run.guid, access)
    Quit $$$OK
}

/// Signs in on `instance` with the wallet secret `secretName`: the platform's answer on 200,
/// otherwise "" with the start-failure `reason`. `unreachable` = 1 when no HTTP answer came and the
/// secret itself was not refused.
ClassMethod SignIn(baseUrl As %String, secretName As %String, instance As %String, Output reason As %String, Output unreachable As %Boolean) As %DynamicObject
{
    Set reason = "", unreachable = 0, httpStatus = 0, transportError = "", secretRefused = 0
    Set answer = ##class(sentai.dispatch.AdminApiClient).LoginWithSecret(baseUrl, secretName, .httpStatus, .transportError, .secretRefused)
    Quit:((httpStatus = 200) && $IsObject(answer) && (answer."access_token" '= "")) answer
    If secretRefused {
        Set reason = "could not read the stored credential for "_instance_": "_transportError
    } ElseIf (httpStatus = 0) {
        Set unreachable = 1
        Set reason = "could not sign in to "_instance_": "_transportError
    } Else {
        Set text = $S($IsObject(answer) && $IsObject(answer."status") && (answer."status"."summary" '= ""):" "_answer."status"."summary", 1:"")
        Set reason = "could not sign in to "_instance_": HTTP "_httpStatus_text
    }
    Quit ""
}

/// Data-model §4: a failed run with no step runs and one log entry; returns the error status the
/// task reports to the platform.
ClassMethod StartFailed(flowId As %String, runAs As %String, reason As %String) As %Status
{
    Try {
        Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 0)
        Set now = $ZDATETIME($HOROLOG, 3)
        Set run = ##class(sentai.model.Run).%New()
        Set run.guid = $SYSTEM.Util.CreateGUID()
        Do run.flowSetObjectId(flowId)
        Set run.flowRevision = $S($IsObject(flow):flow.revision, 1:0)
        Set run.dispatchedBy = runAs, run.trigger = "scheduled", run.state = "failed"
        Set run.startedAt = now, run.finishedAt = now
        $$$ThrowOnError(run.%Save())
        Do ##class(sentai.dispatch.WaveDispatcher).IndexRun(run.guid, flowId, run.flowRevision, now, runAs)
        Do ##class(sentai.dispatch.RunNarrator).ScheduledStartFailed(run.%Id(), reason)
    } Catch ex {
        Set reason = reason_" (and the failed run could not be recorded: "_ex.DisplayString()_")"
    }
    Quit $$$ERROR($$$GeneralError, "SentaiTask scheduled run could not start: "_reason)
}

/// Every error of a validation report, as "#<step> <code> <message>; …".
ClassMethod ReportText(report As %DynamicObject) As %String
{
    Set out = ""
    Quit:'$IsObject(report) ""
    Quit:'$IsObject(report."errors") ""
    Set it = report."errors".%GetIterator()
    While it.%GetNext(.k, .e) { Set out = out_$S(out = "":"", 1:"; ")_$S(e.stepId '= "":"#"_e.stepId_" ", 1:"")_e.code_" "_e.message }
    Quit out
}

}
