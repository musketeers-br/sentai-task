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
ClassMethod SatisfiesInvariant(defaultWorkers As %Integer, maxActiveWorkers As %Integer, maxWorkers As %Integer, maxTotalWorkers As %Integer) As %Boolean
{
    Quit (defaultWorkers <= maxActiveWorkers) && (maxActiveWorkers <= maxWorkers) && (maxWorkers <= maxTotalWorkers)
}

/// Refreshes (or creates) the local mirror row after a confirmed passthrough write to the
/// administrative API — never called as a standalone "local write" (research.md).
ClassMethod Mirror(name As %String, defaultWorkers As %Integer, maxActiveWorkers As %Integer, maxWorkers As %Integer, maxTotalWorkers As %Integer, alwaysQueue As %Boolean) As %Status
{
    Set sc = $$$OK
    Try {
        Set id = ..NameIndexOpen(name, 0, .sc)
        If (id = "") {
            Set cat = ..%New()
            Set cat.name = name
        } Else {
            Set cat = ..%OpenId(id, 4, .sc)
            If $$$ISERR(sc) Throw
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
<Type>%Storage.Persistent</Type>
}

}
