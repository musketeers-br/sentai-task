/// A named, versioned graph of steps an operator composes (FR-001–FR-009).
/// Shape identical to specs/002-canvas-ui/contracts/data-model.md — no field added here.
Class sentai.model.Flow Extends (%Persistent, %JSON.Adaptor)
{

Property name As %String(COLLATION = "SQLUPPER", MAXLEN = 128) [ Required ];

Property revision As %Integer [ InitialExpression = 1 ];

Property savedAt As %TimeStamp;

Property savedBy As %String(MAXLEN = 64);

Property defaultCategory As %String(MAXLEN = 64) [ InitialExpression = "SENTAI.DEFAULT" ];

Property scheduleSpec As %String(MAXLEN = 256);

/// Presentation only (position, viewport). MUST NOT be read by validation or dispatch (FR-009).
Property canvasGeometry As %Stream.GlobalCharacter;

/// Unique, case-insensitive per instance (FR-005). SQLUPPER collation on `name` makes this
/// index effectively case-insensitive without a duplicated shadow property.
Index NameIndex On name [ Unique ];

/// Every step, edge and join belonging to this flow — used by SaveGraph()/read, never by
/// canvasGeometry.
Relationship steps As sentai.model.Step [ Cardinality = many, Inverse = flow ];

Relationship edges As sentai.model.Edge [ Cardinality = many, Inverse = flow ];

Relationship joins As sentai.model.Join [ Cardinality = many, Inverse = flow ];

/// Transactional save of the whole graph (steps + edges + joins) plus the revision bump
/// (research.md R-011). `payload` is the FlowDefinition %DynamicObject already parsed by
/// the REST layer. Returns the persisted flow id via `id`, or a %Status error:
///   $$$ERROR("SentaiNameConflict")   — duplicate name (FR-005)
///   $$$ERROR("SentaiStaleRevision")  — save against a revision that is no longer current (FR-006)
///   $$$ERROR("SentaiCycle", stepId)  — the submitted edge set is cyclic (FR-007)
ClassMethod SaveGraph(payload As %DynamicObject, existingId As %String = "", expectedRevision As %Integer = 0, savedBy As %String = "", ByRef id As %String) As %Status
{
    Set sc = $$$OK
    TSTART
    Try {
        If (existingId '= "") {
            Set flow = ..%OpenId(existingId, 4, .sc)
            $$$ThrowOnError(sc)
            If (flow.revision '= expectedRevision) {
                $$$ThrowStatus($$$ERROR($$$GeneralError, "SentaiStaleRevision: flow was saved by someone else since it was loaded"))
            }
        } Else {
            Set flow = ..%New()
            Set flow.revision = 1
        }

        // NameIndex is SQLUPPER-collated, so the index lookup is already case-insensitive.
        If ..NameIndexExists(payload.name, .conflictId) && (conflictId '= existingId) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "SentaiNameConflict: a flow named '"_payload.name_"' already exists"))
        }

        Set flow.name = payload.name
        If payload.%IsDefined("defaultCategory") Set flow.defaultCategory = payload.defaultCategory
        Set flow.savedAt = $ZDATETIME($HOROLOG, 3)
        Set flow.savedBy = savedBy
        If (existingId '= "") Set flow.revision = flow.revision + 1

        If payload.%IsDefined("canvasGeometry") {
            Do flow.canvasGeometry.Clear()
            Do flow.canvasGeometry.Write(payload.canvasGeometry.%ToJSON())
        }

        Set sc = flow.%Save()
        $$$ThrowOnError(sc)

        // Replace the step/edge/join set atomically within the same transaction.
        Set sc = ##class(sentai.model.Step).ReplaceAll(flow.%Id(), payload."steps")
        $$$ThrowOnError(sc)

        Set sc = ##class(sentai.model.Edge).ReplaceAll(flow.%Id(), payload."edges")
        $$$ThrowOnError(sc)

        Set sc = ##class(sentai.model.Join).ReplaceAll(flow.%Id(), payload."joins")
        $$$ThrowOnError(sc)

        Set id = flow.%Id()
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
<Data name="FlowDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>name</Value>
</Value>
<Value name="3">
<Value>revision</Value>
</Value>
<Value name="4">
<Value>savedAt</Value>
</Value>
<Value name="5">
<Value>savedBy</Value>
</Value>
<Value name="6">
<Value>defaultCategory</Value>
</Value>
<Value name="7">
<Value>scheduleSpec</Value>
</Value>
<Value name="8">
<Value>canvasGeometry</Value>
</Value>
</Data>
<DataLocation>^sentai.model.FlowD</DataLocation>
<DefaultData>FlowDefaultData</DefaultData>
<IdLocation>^sentai.model.FlowD</IdLocation>
<IndexLocation>^sentai.model.FlowI</IndexLocation>
<StreamLocation>^sentai.model.FlowS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
