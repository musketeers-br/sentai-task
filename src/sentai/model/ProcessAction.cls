/// Spec 018 US5 (clarification Q3, data-model §5): one process action the product sent to the
/// platform, with the platform's answer verbatim. Append-only history: nothing reads it to decide
/// whether a later action is allowed (Constitution III). It is not a run.
Class sentai.model.ProcessAction Extends %Persistent
{

/// SQL names avoid reserved words (AT, ACTION), as the "Join" table taught (spec 010).
Property at As %TimeStamp [ Required, SqlFieldName = actedAt ];

Property operator As %String(MAXLEN = 128) [ Required, SqlFieldName = operatorName ];

Property pid As %Integer [ Required ];

Property action As %String(VALUELIST = ",suspend,resume,terminate") [ Required, SqlFieldName = processAction ];

/// The platform's HTTP status; 0 when it did not answer.
Property httpStatus As %Integer;

Property accepted As %Boolean [ InitialExpression = 0 ];

/// The platform's `status` object as JSON, verbatim.
Property platformStatus As %String(MAXLEN = "");

Index AtIndex On at;

/// Appends one record. Returns the saved object's id.
ClassMethod Record(operator As %String, pid As %Integer, action As %String, httpStatus As %Integer, accepted As %Boolean, platformStatus As %DynamicObject, Output id As %String) As %Status
{
    Set rec = ..%New()
    Set rec.at = $ZDATETIME($HOROLOG, 3), rec.operator = operator, rec.pid = pid, rec.action = action
    Set rec.httpStatus = httpStatus, rec.accepted = accepted
    Set rec.platformStatus = $S($IsObject(platformStatus):platformStatus.%ToJSON(), 1:"")
    Set sc = rec.%Save()
    Set id = $S($$$ISOK(sc):rec.%Id(), 1:"")
    Quit sc
}

}
