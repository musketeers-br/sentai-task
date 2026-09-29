/// Spec 011: the embedded catalog prose, one row per entry of the closed step-type catalog.
///
/// This is a **cache of reviewed prose**, not a list of capabilities. Every row is produced from
/// `sentai.registry.StepType.GetCatalog()`, and the catalog stays the only place a capability is
/// declared (FR-013, FR-016, Constitution II): a `type` not in the catalog is never written here,
/// and search reads this table by `type` alone.
///
/// The id key is the catalog's own `type`, so a rebuild is an idempotent upsert per entry plus a
/// delete of types that have left the catalog, and two concurrent rebuilds converge on the same
/// state without a lock (R-005).
Class sentai.search.StepCorpus Extends %Persistent
{

/// The catalog entry's `type`, verbatim. Never invented.
///
/// Declared first, which is what makes it the id key: the whole table is addressed by the catalog
/// type and by nothing else, so a rebuild is an upsert on this one value.
Property type As %String(MAXLEN = 100) [ Required ];

/// The entry's reviewed prose, copied verbatim from the catalog. Required and non-empty: an entry
/// with no prose cannot be embedded, and embedding nothing would rank it against a meaningless
/// vector (FR-014, FR-015). The length is generous enough that no catalog entry can ever be
/// truncated, since a truncated description is a silently wrong embedding.
Property description As %String(MAXLEN = 32000) [ Required ];

/// The embedded `description`.
///
/// Declared with **no length** on purpose. A lengthless column is rejected by `VECTOR_COSINE`
/// directly, while the `TO_VECTOR(vector)` the query already performs satisfies it (R-001). The
/// `%Library.Embedding` type was rejected instead: it resolves its length through a named row in
/// the platform's configuration table, which a persistent class cannot name, and that creates the
/// compile-order cycle documented in R-001a. This form compiles with no configuration row present
/// at all, so the class loads in an environment where no provider is configured — the state the
/// feature has to survive.
Property vector As %Library.Vector;

/// The catalog version this row was built from. A rebuild is triggered by this value differing
/// from the computed current version, never by hand (FR-017, R-005).
Property corpusVersion As %String(MAXLEN = 64);

/// When the row was last embedded. Diagnostic only: currency is decided by `corpusVersion`, not by
/// a timestamp comparison.
Property embeddedAt As %TimeStamp;

/// Spec 017: the identity of the provider that embedded this row —
/// `<config name>|<provider class>|<model>|<vector length>` (data-model §2). A vector means something
/// only for the model that produced it, so a row whose identity is not the current provider's is
/// stale even when its width still matches (FR-007). Never holds any other configuration key, so a
/// secret such as `apiKey` is never copied here (Constitution III).
Property providerIdentity As %String(MAXLEN = 512);

Storage Default
{
<Data name="StepCorpusDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>type</Value>
</Value>
<Value name="3">
<Value>description</Value>
</Value>
<Value name="4">
<Value>vector</Value>
</Value>
<Value name="5">
<Value>corpusVersion</Value>
</Value>
<Value name="6">
<Value>embeddedAt</Value>
</Value>
<Value name="7">
<Value>providerIdentity</Value>
</Value>
</Data>
<DataLocation>^sentai.search.StepCorpusD</DataLocation>
<DefaultData>StepCorpusDefaultData</DefaultData>
<IdLocation>^sentai.search.StepCorpusD</IdLocation>
<IndexLocation>^sentai.search.StepCorpusI</IndexLocation>
<StreamLocation>^sentai.search.StepCorpusS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
