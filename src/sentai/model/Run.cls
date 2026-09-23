/// An execution of a specific revision of a flow (FR-016, FR-024).
Class sentai.model.Run Extends (%Persistent, %JSON.Adaptor)
{

Property guid As %String(MAXLEN = 36) [ Required ];

Property flow As sentai.model.Flow [ Required ];

Property flowRevision As %Integer [ Required ];

Property startedAt As %TimeStamp;

Property finishedAt As %TimeStamp;

Property dispatchedBy As %String(MAXLEN = 64);

Property state As %String(MAXLEN = 16) [ InitialExpression = "running" ];

/// Internal only — never serialized to the REST response. Bumped on every observable
/// change (a StepRun transition or a new LogEntry) so SSE can detect "what's new since
/// the client's last seen version" (data-model.md, contracts/sse-protocol.md).
Property eventVersion As %Integer [ InitialExpression = 0 ];

Index GuidIndex On guid [ Unique ];

Index FlowIndex On flow;

/// JSON adaptor must never serialize eventVersion in REST bodies.
Parameter %JSONIGNORE = "eventVersion";

/// Atomically increments eventVersion of run `runId` — the only way any caller (StepRun/
/// LogEntry writes) is allowed to bump it, so SSE and 3s-polling never diverge
/// (contracts/sse-protocol.md §Guarantees). A row-level SQL update, locked only until the
/// caller's transaction ends: never an object lock, because the background loop keeps its Run
/// open for the whole run while worker processes transition its steps. A copy of the Run
/// already open in this process is reloaded so it reflects the new value.
ClassMethod BumpEventVersionFor(runId As %String) As %Status
{
    &sql(UPDATE sentai_model.Run SET eventVersion = eventVersion + 1 WHERE %ID = :runId)
    If (SQLCODE '= 0) Quit $$$ERROR($$$SQLError, SQLCODE, $GET(%msg))
    // %OpenId hands back this process's in-memory copy when there is one.
    Set run = ..%OpenId(runId, 0)
    If $IsObject(run) Quit run.%Reload()
    Quit $$$OK
}

Method BumpEventVersion() As %Integer
{
    Do ..BumpEventVersionFor(..%Id())
    Quit ..eventVersion
}

/// Duration figures reported separately, never collapsed into a ratio (FR-024).
Method TotalDurationMs() As %Integer
{
    If (..startedAt = "") Quit 0
    Set endTs = $S(..finishedAt '= "":..finishedAt, 1:$ZDATETIME($HOROLOG, 3))
    Quit ##class(sentai.model.Run).MillisecondsBetween(..startedAt, endTs)
}

ClassMethod MillisecondsBetween(t1 As %TimeStamp, t2 As %TimeStamp) As %Integer
{
    Set h1 = $ZDATETIMEH(t1, 3), h2 = $ZDATETIMEH(t2, 3)
    Quit ($P(h2, ",", 1) - $P(h1, ",", 1)) * 86400000 + ($P(h2, ",", 2) - $P(h1, ",", 2)) * 1000
}

Storage Default
{
<Data name="RunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>guid</Value>
</Value>
<Value name="3">
<Value>flow</Value>
</Value>
<Value name="4">
<Value>flowRevision</Value>
</Value>
<Value name="5">
<Value>startedAt</Value>
</Value>
<Value name="6">
<Value>finishedAt</Value>
</Value>
<Value name="7">
<Value>dispatchedBy</Value>
</Value>
<Value name="8">
<Value>state</Value>
</Value>
<Value name="9">
<Value>eventVersion</Value>
</Value>
</Data>
<DataLocation>^sentai.model.RunD</DataLocation>
<DefaultData>RunDefaultData</DefaultData>
<IdLocation>^sentai.model.RunD</IdLocation>
<IndexLocation>^sentai.model.RunI</IndexLocation>
<StreamLocation>^sentai.model.RunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
