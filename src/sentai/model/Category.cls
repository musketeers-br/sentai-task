/// Local mirror of a Work Queue Manager category — NOT the source of truth. Exists only so
/// sentai.wqm.CategoryService can compute affectedTaskCount without an expensive cross-query
/// on every read; every write is an immediate passthrough to the administrative API, never
/// a local write that diverges from the platform (data-model.md).
Class sentai.model.Category Extends (%Persistent, %JSON.Adaptor)
{

Property name As %String(MAXLEN = 64) [ Required ];

Property defaultWorkers As %Integer;

Property maxActiveWorkers As %Integer;

Property maxWorkers As %Integer;

Property maxTotalWorkers As %Integer;

Property alwaysQueue As %Boolean;

Index NameIndex On name [ Unique ];

/// The nesting invariant every write MUST satisfy (FR-034):
/// defaultWorkers <= maxActiveWorkers <= maxWorkers <= maxTotalWorkers.
/// Per Config.WorkQueues, MaxTotalWorkers applies only "if non-zero": 0 means no ceiling,
/// as on the platform's built-in categories, so the last clause is skipped for 0.
ClassMethod SatisfiesInvariant(defaultWorkers As %Integer, maxActiveWorkers As %Integer, maxWorkers As %Integer, maxTotalWorkers As %Integer) As %Boolean
{
    Quit (defaultWorkers <= maxActiveWorkers) && (maxActiveWorkers <= maxWorkers) && ((+maxTotalWorkers = 0) || (maxWorkers <= maxTotalWorkers))
}

/// Refreshes (or creates) the local mirror row after a confirmed passthrough write to the
/// administrative API — never called as a standalone "local write" (research.md).
ClassMethod Mirror(name As %String, defaultWorkers As %Integer, maxActiveWorkers As %Integer, maxWorkers As %Integer, maxTotalWorkers As %Integer, alwaysQueue As %Boolean) As %Status
{
    Set sc = $$$OK
    Try {
        If ..NameIndexExists(name) {
            Set cat = ..NameIndexOpen(name, 4, .sc)
            $$$ThrowOnError(sc)
        } Else {
            Set cat = ..%New()
            Set cat.name = name
        }
        Set cat.defaultWorkers = defaultWorkers
        Set cat.maxActiveWorkers = maxActiveWorkers
        Set cat.maxWorkers = maxWorkers
        Set cat.maxTotalWorkers = maxTotalWorkers
        Set cat.alwaysQueue = alwaysQueue
        Set sc = cat.%Save()
    }
    Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

Storage Default
{
<Data name="CategoryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>name</Value>
</Value>
<Value name="3">
<Value>defaultWorkers</Value>
</Value>
<Value name="4">
<Value>maxActiveWorkers</Value>
</Value>
<Value name="5">
<Value>maxWorkers</Value>
</Value>
<Value name="6">
<Value>maxTotalWorkers</Value>
</Value>
<Value name="7">
<Value>alwaysQueue</Value>
</Value>
</Data>
<DataLocation>^sentai.model.CategoryD</DataLocation>
<DefaultData>CategoryDefaultData</DefaultData>
<IdLocation>^sentai.model.CategoryD</IdLocation>
<IndexLocation>^sentai.model.CategoryI</IndexLocation>
<StreamLocation>^sentai.model.CategoryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
