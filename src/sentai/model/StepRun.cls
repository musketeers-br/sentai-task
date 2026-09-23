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
</Data>
<DataLocation>^sentai.model.StepRunD</DataLocation>
<DefaultData>StepRunDefaultData</DefaultData>
<IdLocation>^sentai.model.StepRunD</IdLocation>
<IndexLocation>^sentai.model.StepRunI</IndexLocation>
<StreamLocation>^sentai.model.StepRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
