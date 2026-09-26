/// An execution of a step within a run — the sole owner of state transitions (FR-022).
/// No caller writes `state` directly; every transition goes through TransitionTo(),
/// which validates against the static table below before writing.
Class sentai.model.StepRun Extends (%Persistent, %JSON.Adaptor)
{

Property guid As %String(MAXLEN = 36) [ Required ];

Property run As sentai.model.Run [ Required ];

Property stepId As %String(MAXLEN = 8) [ Required ];

Property state As %String(MAXLEN = 16) [ InitialExpression = "queued" ];

Property timeQueued As %TimeStamp [ Required ];

Property timeStarted As %TimeStamp;

Property timeFinished As %TimeStamp;

/// Verbatim from the platform — never summarized, reworded, or truncated (FR-023).
Property failureReason As %String(MAXLEN = 2000);

Property progressCurrent As %Integer;

Property progressTotal As %Integer;

Property confirmedBy As %String(MAXLEN = 64);

Property confirmedAt As %TimeStamp;

/// The administrative-API async job identifier this StepRun is tracking (opaque; used
/// internally by WaveDispatcher to poll /api/admin/v1/async-result). Never serialized.
Property adminJobId As %String(MAXLEN = 128);

Parameter %JSONIGNORE = "adminJobId";

/// JSON text the in-process worker copied from the task's `Result` (spec 005), at most 8000
/// characters — InProcessExecutor truncates larger results keeping valid JSON. "" otherwise.
Property result As %String(MAXLEN = 8000);

/// $USERNAME of the worker that ran an in-process step (spec 005 ID-4); "" for management-API steps.
Property executedAs As %String(MAXLEN = 160);

/// Seconds TransitionLocked waits for the StepRun's exclusive lock.
Parameter LOCKTIMEOUT = 5;

Index GuidIndex On guid [ Unique ];

Index RunStepIndex On (run, stepId);

/// The current StepRun of `stepId` within run `runId`. RunStepIndex is not unique — a
/// rerun (FR-030) adds a new StepRun for the same step — so the latest one wins, the same
/// one ^sentaiRun(runGuid, stepId) points at. Returns "" when none exists.
ClassMethod OpenForRunStep(runId As %String, stepId As %String, concurrency As %Integer = -1, Output sc As %Status) As sentai.model.StepRun
{
    Set sc = $$$OK
    &sql(SELECT TOP 1 %ID INTO :stepRunId FROM sentai_model.StepRun WHERE run = :runId AND stepId = :stepId ORDER BY %ID DESC)
    If (SQLCODE '= 0) Quit ""
    Quit ..%OpenId(stepRunId, concurrency, .sc)
}

/// The six-state machine's legal-transition table (data-model.md), enforced here so no
/// code path can ever produce an illegal transition:
///   completed -> *, failed -> *, cancelled -> * : forbidden (all three are terminal)
///   queued -> running                            : requires guid already set (always true here)
///   queued -> paused                              : forbidden
ClassMethod IsLegalTransition(fromState As %String, toState As %String) As %Boolean
{
    If (fromState = toState) Quit 0
    If (fromState = "completed") Quit 0
    If (fromState = "failed") Quit 0
    If (fromState = "cancelled") Quit 0
    If ((fromState = "queued") && (toState = "paused")) Quit 0
    Quit 1
}

/// The sole writer of `state`. Validates the transition, stamps timeStarted/timeFinished
/// as appropriate, stores failureReason verbatim, and bumps the owning Run's eventVersion
/// within the same transaction (FR-022, FR-023, contracts/sse-protocol.md).
Method TransitionTo(newState As %String, failureReason As %String = "") As %Status
{
    Set sc = $$$OK
    TSTART
    Try {
        If '..IsLegalTransition(..state, newState) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "SentaiIllegalTransition: "_..state_" -> "_newState_" is not allowed"))
        }

        Set ..state = newState
        If (newState = "running") && (..timeStarted = "") Set ..timeStarted = $ZDATETIME($HOROLOG, 3)
        If $LISTFIND($LB("completed", "failed", "cancelled"), newState) Set ..timeFinished = $ZDATETIME($HOROLOG, 3)
        If (newState = "failed") && (failureReason '= "") Set ..failureReason = failureReason

        Set sc = ..%Save()
        $$$ThrowOnError(sc)

        $$$ThrowOnError(##class(sentai.model.Run).BumpEventVersionFor(..runGetObjectId()))

        TCOMMIT
    }
    Catch ex {
        TROLLBACK 1
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The transition used by writers that may race (spec 005 plan item 3): the in-process worker
/// and the run loop's timeout sweep. Takes the StepRun's exclusive lock, re-reads it from disk
/// (a copy already in this process's memory may be stale) and applies TransitionTo, so exactly
/// one terminal state wins and the loser gets SentaiIllegalTransition. A lock timeout is
/// returned unchanged; the caller decides whether to retry. The worker passes `result` and
/// `executedAs`: they are saved with the transition, so a loser records nothing.
ClassMethod TransitionLocked(guid As %String, newState As %String, failureReason As %String = "", result As %String = "", executedAs As %String = "") As %Status
{
    If '..GuidIndexExists(guid, .id) Quit $$$ERROR($$$GeneralError, "SentaiNotFound: step run "_guid)
    Set sc = ..%LockId(id, 0, ..#LOCKTIMEOUT)
    Quit:$$$ISERR(sc) sc
    Try {
        Set stepRun = ..%OpenId(id, 0, .sc)
        If $IsObject(stepRun) {
            Set sc = stepRun.%Reload()
            If $$$ISOK(sc) && ..IsLegalTransition(stepRun.state, newState) {
                Set:(result '= "") stepRun.result = result
                Set:(executedAs '= "") stepRun.executedAs = executedAs
            }
            If $$$ISOK(sc) Set sc = stepRun.TransitionTo(newState, failureReason)
        }
    }
    Catch ex {
        Set sc = ex.AsStatus()
    }
    Do ..%UnlockId(id, 0, 1)
    Quit sc
}

Storage Default
{
<Data name="StepRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>guid</Value>
</Value>
<Value name="3">
<Value>run</Value>
</Value>
<Value name="4">
<Value>stepId</Value>
</Value>
<Value name="5">
<Value>state</Value>
</Value>
<Value name="6">
<Value>timeQueued</Value>
</Value>
<Value name="7">
<Value>timeStarted</Value>
</Value>
<Value name="8">
<Value>timeFinished</Value>
</Value>
<Value name="9">
<Value>failureReason</Value>
</Value>
<Value name="10">
<Value>progressCurrent</Value>
</Value>
<Value name="11">
<Value>progressTotal</Value>
</Value>
<Value name="12">
<Value>confirmedBy</Value>
</Value>
<Value name="13">
<Value>confirmedAt</Value>
</Value>
<Value name="14">
<Value>adminJobId</Value>
</Value>
<Value name="15">
<Value>result</Value>
</Value>
<Value name="16">
<Value>executedAs</Value>
</Value>
</Data>
<DataLocation>^sentai.model.StepRunD</DataLocation>
<DefaultData>StepRunDefaultData</DefaultData>
<IdLocation>^sentai.model.StepRunD</IdLocation>
<IndexLocation>^sentai.model.StepRunI</IndexLocation>
<StreamLocation>^sentai.model.StepRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
