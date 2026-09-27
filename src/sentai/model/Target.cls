/// Spec 008: a target server — another instance of the platform a step may run on. A name and
/// an address only: no credential of any kind is stored here (FR-002); calls to it always carry
/// the operator's own credential for it, obtained at the moment of use.
Class sentai.model.Target Extends %Persistent
{

/// The key in every API path (`^[A-Za-z0-9][A-Za-z0-9._-]*$`, at most 64 characters).
Property name As %String(MAXLEN = 64) [ Required ];

/// `scheme://host:port` — no path, query or user info (data-model.md).
Property baseUrl As %String(MAXLEN = 256) [ Required ];

Property description As %String(MAXLEN = 512);

/// Set only by an operator (FR-004), never from reachability.
Property online As %Boolean [ InitialExpression = 1 ];

Property createdAt As %TimeStamp;

Property createdBy As %String(MAXLEN = 64);

Property updatedAt As %TimeStamp;

Property updatedBy As %String(MAXLEN = 64);

Index NameIndex On name [ Unique ];

/// The API shape (contracts/api-delta.md §Targets).
Method ToJSON() As %DynamicObject
{
    Set out = {"name": (..name), "baseUrl": (..baseUrl), "description": (..description), "createdAt": (..createdAt), "updatedAt": (..updatedAt)}
    Do out.%Set("online", ''..online, "boolean")
    Quit out
}

Storage Default
{
<Data name="TargetDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>name</Value>
</Value>
<Value name="3">
<Value>baseUrl</Value>
</Value>
<Value name="4">
<Value>description</Value>
</Value>
<Value name="5">
<Value>online</Value>
</Value>
<Value name="6">
<Value>createdAt</Value>
</Value>
<Value name="7">
<Value>createdBy</Value>
</Value>
<Value name="8">
<Value>updatedAt</Value>
</Value>
<Value name="9">
<Value>updatedBy</Value>
</Value>
</Data>
<DataLocation>^sentai.model.TargetD</DataLocation>
<DefaultData>TargetDefaultData</DefaultData>
<IdLocation>^sentai.model.TargetD</IdLocation>
<IndexLocation>^sentai.model.TargetI</IndexLocation>
<StreamLocation>^sentai.model.TargetS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
