/// A node of a flow: a step type plus its configuration (FR-001, FR-010, FR-011).
/// `isDestructive` is always derived from `type` via sentai.registry.StepType — never
/// accepted as operator input, even if submitted (FR-010).
Class sentai.model.Step Extends (%Persistent, %JSON.Adaptor)
{

/// Stable within the flow; rendered as "#01", "#02", ... — not globally unique.
Property id As %String(MAXLEN = 8) [ Required ];

Property type As %String(MAXLEN = 48) [ Required ];

Property taskName As %String(MAXLEN = 128) [ Required ];

Property namespace As %String(MAXLEN = 64) [ Required ];

Property databaseDirectory As %String(MAXLEN = 256);

Property runAsUser As %String(MAXLEN = 64);

/// Type-specific; validated against the type's schema by sentai.validation.FlowValidator.
Property parameters As %DynamicObject;

Property timeoutMinutes As %Integer [ InitialExpression = 0 ];

Property wqmCategory As %String(MAXLEN = 64);

/// Required when type = "custom" (FR-011); a subclass of %SYS.Task.Definition.
Property customClass As %String(MAXLEN = 256);

Relationship flow As sentai.model.Flow [ Cardinality = one, Inverse = steps ];

Index FlowIndex On flow;

Index FlowStepIndex On (flow, id) [ Unique ];

/// isDestructive is computed, never stored — the only way to read it is this method,
/// which %JSON.Adaptor exposes via %JSONInclude on JSONFIELD below (FR-010).
Property isDestructive As %Boolean [ Calculated, SqlComputeCode = { Set {isDestructive} = ##class(sentai.registry.StepType).IsDestructive({type}) }, SqlComputed ];

/// Whether this step's type honours pause requests in v1 — purge family only.
Property isPausable As %Boolean [ Calculated, SqlComputeCode = { Set {isPausable} = ##class(sentai.registry.StepType).IsPausable({type}) }, SqlComputed ];

/// Replaces every step of `flow` with the submitted array, inside the caller's transaction.
/// Silently drops any `isDestructive` field present in the payload (FR-010) — it is never
/// read from input.
ClassMethod ReplaceAll(flowId As %String, stepsArray As %DynamicArray) As %Status
{
    Set sc = $$$OK
    Try {
        &sql(DELETE FROM sentai_model.Step WHERE flow = :flowId)
        If (stepsArray = "") Quit

        Set iter = stepsArray.%GetIterator()
        While iter.%GetNext(.k, .stepObj) {
            Set step = ..%New()
            Do step.flowSetObjectId(flowId)
            Set step.id = stepObj.id
            Set step.type = stepObj.type
            Set step.taskName = stepObj.taskName
            Set step.namespace = stepObj.namespace
            If stepObj.%IsDefined("databaseDirectory") Set step.databaseDirectory = stepObj.databaseDirectory
            If stepObj.%IsDefined("runAsUser") Set step.runAsUser = stepObj.runAsUser
            If stepObj.%IsDefined("parameters") Set step.parameters = stepObj.parameters
            If stepObj.%IsDefined("timeoutMinutes") Set step.timeoutMinutes = stepObj.timeoutMinutes
            If stepObj.%IsDefined("wqmCategory") Set step.wqmCategory = stepObj.wqmCategory
            If stepObj.%IsDefined("customClass") Set step.customClass = stepObj.customClass

            Set sc = step.%Save()
            If $$$ISERR(sc) Quit
        }
    }
    Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

Storage Default
{
<Data name="StepDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>flow</Value>
</Value>
<Value name="3">
<Value>id</Value>
</Value>
<Value name="4">
<Value>type</Value>
</Value>
<Value name="5">
<Value>taskName</Value>
</Value>
<Value name="6">
<Value>namespace</Value>
</Value>
<Value name="7">
<Value>databaseDirectory</Value>
</Value>
<Value name="8">
<Value>runAsUser</Value>
</Value>
<Value name="9">
<Value>timeoutMinutes</Value>
</Value>
<Value name="10">
<Value>wqmCategory</Value>
</Value>
<Value name="11">
<Value>customClass</Value>
</Value>
</Data>
<Data name="parameters">
<Attribute>parameters</Attribute>
<Structure>node</Structure>
<Subscript>"parameters"</Subscript>
</Data>
<DataLocation>^sentai.model.StepD</DataLocation>
<DefaultData>StepDefaultData</DefaultData>
<IdLocation>^sentai.model.StepD</IdLocation>
<IndexLocation>^sentai.model.StepI</IndexLocation>
<StreamLocation>^sentai.model.StepS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
