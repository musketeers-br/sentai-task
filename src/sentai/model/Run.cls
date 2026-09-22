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

/// Atomically increments eventVersion and returns the new value — the only way any
/// caller (StepRun/LogEntry writes) is allowed to bump it, so SSE and 3s-polling never
/// diverge (contracts/sse-protocol.md §Guarantees).
Method BumpEventVersion() As %Integer
{
    Set ..eventVersion = ..eventVersion + 1
    Do ..%Save()
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
<Type>%Storage.Persistent</Type>
}

}
