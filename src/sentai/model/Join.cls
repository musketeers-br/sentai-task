/// One entry per target step with two or more incoming edges, carrying the partial-failure
/// policy in force over it. v1 supports only ALL_MUST_SUCCEED (FR-008, FR-021); the other
/// two enum values exist for structural compatibility with the contract only.
Class sentai.model.Join Extends (%Persistent, %JSON.Adaptor)
{

Property flow As sentai.model.Flow [ Required ];

Property target As %String(MAXLEN = 8) [ Required ];

Property policy As %String(MAXLEN = 32) [ InitialExpression = "ALL_MUST_SUCCEED" ];

Property minSucceeded As %Integer;

/// At most one join entry per target step (data-model.md).
Index FlowTargetIndex On (flow, target) [ Unique ];

/// Replaces the flow's join set with the submitted array, then fills in any target step
/// with two or more incoming edges that the payload left implicit — a join entry always
/// exists for every fan-in target, defaulting to ALL_MUST_SUCCEED (FR-008).
ClassMethod ReplaceAll(flowId As %String, joinsArray As %DynamicArray) As %Status
{
    Set sc = $$$OK
    Try {
        &sql(DELETE FROM sentai.model.Join WHERE flow = :flowId)

        If (joinsArray '= "") {
            Set iter = joinsArray.%GetIterator()
            While iter.%GetNext(.k, .joinObj) {
                Set join = ..%New()
                Set join.flow = flowId
                Set join.target = joinObj.target
                Set join.policy = $S(joinObj.%IsDefined("policy"):joinObj.policy, 1:"ALL_MUST_SUCCEED")
                If joinObj.%IsDefined("minSucceeded") Set join.minSucceeded = joinObj.minSucceeded
                Set sc = join.%Save()
                If $$$ISERR(sc) Quit
            }
            If $$$ISERR(sc) Quit
        }

        // Ensure every fan-in target (>=2 incoming edges) has a join entry, per FR-008.
        Set rs = ##class(%SQL.Statement).%New()
        Do rs.%Prepare("SELECT target, COUNT(*) AS c FROM sentai.model.Edge WHERE flow = ? GROUP BY target HAVING COUNT(*) >= 2")
        Set result = rs.%Execute(flowId)
        While result.%Next() {
            Set targetId = result.%Get("target")
            If '..%ExistsId(flowId_"||"_targetId) {
                Set existing = ##class(%SQL.Statement).%New()
                Do existing.%Prepare("SELECT %ID FROM sentai.model.Join WHERE flow = ? AND target = ?")
                Set existingRs = existing.%Execute(flowId, targetId)
                If 'existingRs.%Next() {
                    Set join = ..%New()
                    Set join.flow = flowId
                    Set join.target = targetId
                    Set join.policy = "ALL_MUST_SUCCEED"
                    Set sc = join.%Save()
                    If $$$ISERR(sc) Quit
                }
            }
        }
    }
    Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

Storage Default
{
<Data name="JoinDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>flow</Value>
</Value>
<Value name="3">
<Value>target</Value>
</Value>
<Value name="4">
<Value>policy</Value>
</Value>
<Value name="5">
<Value>minSucceeded</Value>
</Value>
</Data>
<DataLocation>^sentai.model.JoinD</DataLocation>
<DefaultData>JoinDefaultData</DefaultData>
<IdLocation>^sentai.model.JoinD</IdLocation>
<IndexLocation>^sentai.model.JoinI</IndexLocation>
<StreamLocation>^sentai.model.JoinS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
