/// One line of a run's log — the same shape openapi.yaml's RunDetail.log already
/// anticipated (FR-025). Materializes what LogEntry only implied in the 002 contract.
Class sentai.model.LogEntry Extends (%Persistent, %JSON.Adaptor)
{

Property run As sentai.model.Run [ Required ];

Property at As %TimeStamp [ Required ];

Property stepId As %String(MAXLEN = 8);

Property severity As %String(MAXLEN = 16) [ InitialExpression = "info" ];

Property message As %String(MAXLEN = 4000);

/// "Most recent first" read order (FR-025, RunDetail.log).
Index RunAtIndex On (run, at);

/// Writes one log line and bumps the owning Run's eventVersion in the same transaction,
/// so SSE and the 3s-polling fallback never diverge.
ClassMethod Append(runId As %String, stepId As %String, severity As %String, message As %String) As %Status
{
    Set sc = $$$OK
    TSTART
    Try {
        Set entry = ..%New()
        Set entry.run = runId
        Set entry.at = $ZDATETIME($HOROLOG, 3)
        Set entry.stepId = stepId
        Set entry.severity = severity
        Set entry.message = message
        Set sc = entry.%Save()
        If $$$ISERR(sc) Throw

        Set run = ##class(sentai.model.Run).%OpenId(runId, 4, .sc)
        If $$$ISERR(sc) Throw
        Do run.BumpEventVersion()

        TCOMMIT
    }
    Catch ex {
        TROLLBACK 1
        Set sc = $S($$$ISERR($G(sc)):sc, 1:ex.AsStatus())
    }
    Quit sc
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
