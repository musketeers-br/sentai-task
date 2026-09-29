/// Spec 011: semantic search over the closed step-type catalog.
/// 
/// The service owns three things and nothing else: whether a provider is configured, whether the
/// stored corpus still matches the catalog, and the ranking. It reads the catalog only through
/// `##class(sentai.registry.StepType).GetCatalog()` and never a class name (Constitution II, R-009).
/// 
/// Every predictable failure leaves as a value. A missing provider row, an unreachable provider, a
/// provider that is too slow, a dimension the corpus cannot use and an outright error are all
/// `SearchOutcome.Unavailable(..)` on a 200 — never an exception and never a 5xx (Constitution IV,
/// FR-024, R-007). `Search` itself catches, as the outer guard that keeps that promise; everything
/// inside it reads failures as values. SQL failures are read from `%SQLCODE` and `%Message`, and
/// provider failures are read from the caught status of a direct call — which is the one channel
/// that carries the provider's own words (see `EmbedText`).
Class sentai.search.StepSearchService Extends %RegisteredObject
{

/// The `%EMBEDDING.Config` row that names the provider. The endpoint, model and key live in that
/// row, never in this class (R-002).
Parameter EmbeddingConfigName = "sentai-steps";

/// The absolute relevance floor (R-008). Entries below it contribute nothing, so the palette
/// behaves exactly as it does today. Measured on the shipped nine-entry corpus, where the weakest
/// true match scores 0.501 and the best nonsense query reaches 0.053.
Parameter MinScore = 0.2;

/// The modulus that keeps the rolling checksum below double precision. A power of ten rather than
/// a prime, because nothing here is adversarial and readability beats a better distribution.
Parameter ChecksumModulus = 1000000000;

/// The one statement that ranks. Cosine has no `$VOP` arithmetic, so SQL is the only place the
/// comparison can happen (R-001). The query vector arrives as a bound parameter rather than as
/// `EMBEDDING(?, ?)` inside the statement: a provider that throws inside SQL's EMBEDDING() is
/// reported as SQLCODE -400, "Unexpected error occurred", with the provider's own text gone
/// entirely (measured in the T018 probes), so the query is embedded outside the statement —
/// through `EmbedText`, where the full status text and its leading reason token survive — and the
/// vector itself is bound. Both parameters are the vector and nothing operator-typed: the text
/// never reaches SQL.
Parameter RankingSQL = "SELECT Type, VECTOR_COSINE(?, TO_VECTOR(Vector)) AS score FROM sentai_search.StepCorpus ORDER BY score DESC";

/// A corpus row, written with the vector already embedded (see `EmbedText`) and converted through
/// `TO_VECTOR`, which is the same conversion the ranking statement reads the column with.
/// Spec 017: each row also records the identity of the provider that embedded it (FR-007).
Parameter InsertSQL = "INSERT INTO sentai_search.StepCorpus (type, description, vector, corpusVersion, providerIdentity, embeddedAt) VALUES (?, ?, TO_VECTOR(?), ?, ?, NOW())";

/// Ranks the catalog against `q` and returns the answer as a value.
/// 
/// The corpus is built here if it is missing or no longer matches the catalog, so the first
/// request after a catalog change pays for the embedding and every later one reads stored vectors.
ClassMethod Search(q As %String) As sentai.search.SearchOutcome
{
    // The outer guard: anything `SearchInside` did not predict is still a value on a 200 — the
    // `error` reason — and no exception crosses this method (Constitution IV, FR-024).
    Set outcome = ##class(sentai.search.SearchOutcome).Unavailable("error")
    Try {
        Set outcome = ..SearchInside(q)
    } Catch e {
        // Deliberately nothing to read here: the platform's own words are never shown as a
        // message (FR-024), and the palette falls back to today's behaviour either way.
    }
    Quit outcome
}

/// The ranking flow itself. Every branch ends in a `Quit` with an outcome, so `Search` has
/// nothing left to decide.
ClassMethod SearchInside(q As %String) As sentai.search.SearchOutcome
{
    // No provider row is the one condition worth answering without trying: there is nothing to
    // call, so no provider is called (FR-024, `not-configured`). A lookup that itself fails is a
    // different thing, and is reported as `error` rather than disguised as a configuration state
    // the operator would go looking for in a row that is not there.
    Set configured = ..ProviderIsConfigured()
    If (configured < 0) Quit ##class(sentai.search.SearchOutcome).Unavailable("error")
    If (configured = 0) Quit ##class(sentai.search.SearchOutcome).Unavailable("not-configured")

    // The query is embedded before anything is written or read, so a provider that is down
    // answers before a build is attempted and never leaves a partial corpus behind (FR-025).
    Set reason = ""
    Set queryVector = ..EmbedText(q, .reason)
    If (reason '= "") Quit ##class(sentai.search.SearchOutcome).Unavailable(reason)

    Set sc = ..EnsureCorpus(.reason)
    If (sc '= $$$OK) Quit ##class(sentai.search.SearchOutcome).Unavailable(reason)

    // A provider whose width no longer matches the stored corpus cannot rank it, and the
    // mismatch raises no SQL error to be read later — VECTOR_COSINE simply yields no score, so
    // the answer would masquerade as "no results", which is exactly the masquerade FR-023
    // exists to forbid. Measured; the comparison is made here instead.
    If '..WidthsAgree(queryVector) Quit ##class(sentai.search.SearchOutcome).Unavailable("incompatible")

    Set rs = ##class(%SQL.Statement).%ExecDirect(, ..#RankingSQL, queryVector)
    If (rs.%SQLCODE < 0) Quit ##class(sentai.search.SearchOutcome).Unavailable(..ReasonFromMessage(rs.%Message))

    Set matches = ..Ranked(rs)
    If (matches.%Size() = 0) Quit ##class(sentai.search.SearchOutcome).NoMatches()
    Quit ##class(sentai.search.SearchOutcome).Available(matches)
}

/// Embeds one text through the row the platform holds, catching the provider's own status so the
/// reason it named survives into the answer.
/// 
/// The dispatch is the same one the platform's EMBEDDING() performs — the row's `EmbeddingClass`
/// with the row's `Configuration` — and the row is operator configuration in the platform's own
/// table, never something request-typed (Constitution II). Nothing here names a provider, so
/// pointing a deployment elsewhere is a row change and not a code change (FR-012).
/// 
/// On failure, `reason` is one of the provider conditions and the return is ""; on success the
/// return is the provider's vector — a scalar datatype value, not an oref — and `reason` is "".
ClassMethod EmbedText(text As %String, Output reason As %String)
{
    Set reason = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EmbeddingClass, Configuration FROM %EMBEDDING.Config WHERE Name = ?", ..#EmbeddingConfigName)
    If (rs.%SQLCODE < 0) {
        Set reason = "error"
        Quit ""
    }
    If 'rs.%Next() {
        Set reason = "not-configured"
        Quit ""
    }
    Set providerClass = rs.%Get("EmbeddingClass"), configuration = rs.%Get("Configuration")
    Set vector = ""
    Try {
        Set vector = $CLASSMETHOD(providerClass, "Embedding", text, configuration)
    } Catch e {
        // The full status text — "…Embedding error: <token>: …" — is what carries the provider's
        // classification; %Exception has no readable Status property on this platform build, so
        // AsStatus() is the accessor (measured on IRIS 2026.2).
        Set reason = ..ReasonFromMessage(##class(%SYSTEM.Status).GetErrorText(e.AsStatus()))
    }
    // A provider that answered neither a vector nor a failure is itself a defect: `error`, never
    // a silent empty ranking.
    If (reason = ""), (vector = "") Set reason = "error"
    Quit vector
}

/// Reads the ranked rows and returns only those at or above the floor, best first.
/// 
/// The ordering is done here rather than left to `ORDER BY score DESC`, because SQL says nothing
/// about how it breaks a tie. A tie is broken by catalog order, so the same query always offers
/// the same palette and a stable corpus never reorders itself under the operator.
ClassMethod Ranked(rs) As %DynamicArray
{
    Set rows = ##class(%DynamicArray).%New()
    While rs.%Next() {
        Set label = rs.%Get("Type"), score = +rs.%Get("score")
        Set position = ..CatalogPosition(label)
        // Built property by property: an object literal here would have to be all literals in this
        // compiler (R-014), and the point of this row is a value read from the result set.
        Set row = ##class(%DynamicObject).%New()
        Set row.type = label, row.score = score, row.position = position
        Do rows.%Push(row)
    }

    // Insertion sort: stable, and small enough to read at a glance for a catalog this size.
    // `%DynamicArray` is indexed from zero, so the counter starts there too.
    Set howMany = rows.%Size(), i = 0
    For i = 0:1:(howMany - 1) {
        Set held = rows.%Get(i), j = i - 1
        While (j >= 0) && (..ComesBefore(held, rows.%Get(j))) {
            Set shifted = rows.%Get(j)
            Do rows.%Set(j + 1, shifted)
            Set j = j - 1
        }
        Do rows.%Set(j + 1, held)
    }

    Set matches = ##class(%DynamicArray).%New(), i = 0
    For i = 0:1:(howMany - 1) {
        Set row = rows.%Get(i)
        If (row.score >= ..#MinScore) {
            Set kept = ##class(%DynamicObject).%New()
            Set kept.type = row.type, kept.score = row.score
            Do matches.%Push(kept)
        }
    }
    Quit matches
}

/// True when `held` belongs above `other`: a higher score wins, and catalog order settles a tie.
ClassMethod ComesBefore(held, other) As %Boolean
{
    If (held.score > other.score) Quit 1
    If (held.score < other.score) Quit 0
    Quit held.position < other.position
}

/// A type's place in the catalog, used only as the tiebreaker. A type the catalog does not name
/// sorts last among equals, so a stray row can never displace a real entry.
ClassMethod CatalogPosition(type As %String) As %Integer
{
    Set position = -1, index = 0, searching = 1
    Set iter = ##class(sentai.registry.StepType).GetCatalog().%GetIterator()
    While (searching = 1) && iter.%GetNext(.key, .entry) {
        If (entry.type = type) {
            Set position = index
            Set searching = 0
        } Else {
            Set index = index + 1
        }
    }
    If (position < 0) Set position = 1000000
    Quit position
}

/// Builds the corpus when it is missing or no longer describes the catalog, and does nothing when
/// it does. `reason` is set only when a build fails, and is then one of the provider conditions.
/// 
/// Every vector is embedded before the first row is written, so a provider that fails partway
/// leaves the corpus exactly as it was — empty or complete, never a half-built one (FR-025).
ClassMethod EnsureCorpus(Output reason As %String) As %Status
{
    Set reason = ""
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    If ..CorpusIsCurrent(catalog) Quit $$$OK

    Set vectors = ##class(%DynamicArray).%New()
    Set iter = catalog.%GetIterator(), sc = $$$OK
    // The loop is guarded by the status rather than left with a `Quit` inside the block, because a
    // `Quit` carrying a value is rejected there (R-014). A partial corpus is never left behind
    // silently: the status and the reason leave together.
    //
    // FR-018, R-009 — the constraint, visible: each row's embedding source is `entry.description`
    // and nothing else. The entry's `class` is never read on this path, because the legacy
    // `custom` entry carries an empty one and a builder that read it would embed empty text for
    // that entry and silently make it unfindable — the exact failure US3 exists to prevent.
    // `TestClassNamesAreNotSearchKeys` and `TestCorpusRowIsDerivedFromTheDescription` hold it.
    While (sc = $$$OK) && iter.%GetNext(.key, .entry) {
        Set vector = ..EmbedText(entry.description, .reason)
        If (reason '= "") {
            Set sc = $$$ERROR($$$GeneralError, "embedding failed for "_entry.type)
        } Else {
            // The display form is what TO_VECTOR converts on the way in — the same conversion the
            // ranking statement reads the column with.
            Do vectors.%Push(##class(%Library.Vector).LogicalToDisplay(vector))
        }
    }
    If (sc '= $$$OK) Quit sc

    // Rebuilt, not amended: a catalog that lost a type must not leave that type's vector behind.
    &sql(DELETE FROM sentai_search.StepCorpus)
    Set identity = ..ProviderIdentity()
    Set version = ..CorpusVersion(catalog, identity)
    Set iter = catalog.%GetIterator(), i = 0
    While (sc = $$$OK) && iter.%GetNext(.key, .entry) {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, ..#InsertSQL, entry.type, entry.description, vectors.%Get(i), version, identity)
        Set i = i + 1
        If (rs.%SQLCODE < 0) {
            Set reason = ..ReasonFromMessage(rs.%Message)
            Set sc = $$$ERROR($$$SQLError, rs.%SQLCODE, "corpus row for "_entry.type)
        }
    }
    Quit sc
}

/// Whether every stored row still matches the catalog, by type and by description, and was
/// embedded by the provider configured now.
/// 
/// The comparison is against the catalog itself rather than against the version stamp, so no
/// checksum collision can leave a stale vector behind being offered to the operator (R-005).
/// With a dozen rows this costs one small read, and it is the only question asked per request.
/// 
/// Spec 017 FR-007: the provider identity is part of currency. A provider swapped for another of
/// the same width passes `WidthsAgree`, so without this the new provider's queries would be ranked
/// against the old provider's vectors — meaningless scores that still look like results.
ClassMethod CorpusIsCurrent(catalog As %DynamicArray) As %Boolean
{
    // `stored` is an ordinary local array, created by its first assignment; a `New` is not
    // available in a class method and `[]` subscripts are rejected (R-014).
    Set howMany = 0, sameProvider = 1, identity = ..ProviderIdentity()
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Type, description, providerIdentity FROM sentai_search.StepCorpus")
    If (rs.%SQLCODE < 0) Quit 0
    While rs.%Next() {
        Set howMany = howMany + 1
        If (rs.%Get("providerIdentity") '= identity) Set sameProvider = 0
        // The column values are read into locals first: a `%Get` call is not accepted directly
        // in subscript position by this compiler (R-014), and this line is not worth a hang.
        Set label = rs.%Get("Type"), storedText = rs.%Get("description")
        Set stored(label) = storedText
    }
    If (howMany '= catalog.%Size()) Quit 0
    If ('sameProvider) Quit 0

    Set iter = catalog.%GetIterator(), current = 1
    While (current = 1) && iter.%GetNext(.key, .entry) {
        If ($G(stored(entry.type)) '= entry.description) Set current = 0
    }
    Quit current
}

/// A stamp for the corpus, derived from the catalog so a catalog change is visible in the data.
/// 
/// A pure function of the catalog it is handed (T028) and of the provider identity (spec 017; the
/// current one when none is given): a hash over the identity and the catalog's
/// `(type, description)` pairs in catalog order — and nothing else, so rewording a `label` does
/// not invalidate the corpus (data-model §2). Category, executor, availability, destructiveness
/// and `class` are all excluded, and the exclusion is what T027's tests hold.
/// 
/// No hash intrinsic or hash class exists on this platform build (R-014), so this is a rolling
/// checksum rather than a digest. It is deliberately not load-bearing: `CorpusIsCurrent` decides
/// staleness by comparing the catalog, so a collision costs a wrong-looking stamp and nothing else.
ClassMethod CorpusVersion(catalog As %DynamicArray, identity As %String = "") As %String
{
    If (identity = "") Set identity = ..ProviderIdentity()
    Set text = identity_";"
    Set iter = catalog.%GetIterator()
    While iter.%GetNext(.key, .entry) {
        Set text = text_entry.type_"="_$EXTRACT(entry.description, 1, 2000)
    }
    Set total = 0, rolling = 0, i = 0
    For i = 1:1:($LENGTH(text)) {
        Set code = $ASCII($EXTRACT(text, i))
        Set total = total + code
        Set rolling = ((rolling * 33) + code) # ..#ChecksumModulus
    }
    Quit "v2-"_$LENGTH(text)_"-"_total_"-"_rolling
}

/// Spec 017, data-model §2: what a stored vector means —
/// `<config name>|<provider class>|<model>|<vector length>`, read from the `sentai-steps` row.
/// 
/// `<model>` is the configuration's `model`, else its `modelName`, else empty; no other key is
/// read, so a secret such as `apiKey` never reaches the corpus (Constitution III). "" when there
/// is no row.
ClassMethod ProviderIdentity() As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EmbeddingClass, Configuration, VectorLength FROM %EMBEDDING.Config WHERE Name = ?", ..#EmbeddingConfigName)
    If (rs.%SQLCODE < 0) || ('rs.%Next()) Quit ""
    Set model = ""
    Try {
        Set cfg = ##class(%DynamicObject).%FromJSON(rs.%Get("Configuration"))
        Set model = cfg.%Get("model")
        If (model = "") Set model = cfg.%Get("modelName")
    } Catch e {
        // A configuration the platform accepted but this cannot parse still has a class and a
        // length; the identity is simply less specific.
    }
    Quit ..#EmbeddingConfigName_"|"_rs.%Get("EmbeddingClass")_"|"_model_"|"_rs.%Get("VectorLength")
}

/// Whether the provider row exists: `1` present, `0` absent, `-1` the lookup itself failed.
/// 
/// The check is deliberately a lookup rather than an attempt: with no row there is nothing to
/// call, and calling anyway would turn a configuration state into an error. The third answer is
/// not decoration — `FOUND` is a reserved word, and an illegal statement used to be reported here
/// as "not configured", which is a wrong answer rather than a missing one.
ClassMethod ProviderIsConfigured() As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS present FROM %EMBEDDING.Config WHERE Name = ?", ..#EmbeddingConfigName)
    If (rs.%SQLCODE < 0) Quit -1
    Set present = 0
    If rs.%Next() Set present = +rs.%Get("present")
    Quit present > 0
}

/// True when the query vector's width is the width the stored corpus was built with.
/// 
/// An absent corpus cannot mismatch, and `EnsureCorpus` has already run by the time this is asked,
/// so the only `0` this can return is the real condition: the row was re-pointed at a provider of
/// a different width since the corpus was stored.
ClassMethod WidthsAgree(vector) As %Boolean
{
    Set storedWidth = ..StoredWidth()
    If (storedWidth = 0) Quit 1
    Quit (storedWidth = ..WidthOf(vector))
}

/// A vector's width: the number of components in its display form, which is the bracketed,
/// comma-separated list the vector type itself converts. A `%Vector` is a scalar datatype value,
/// not an oref (measured: `$IsObject` is 0 on it), so the count is taken from the text.
ClassMethod WidthOf(vector) As %Integer
{
    Quit $LENGTH(##class(%Library.Vector).LogicalToDisplay(vector), ",")
}

/// The width of the corpus as stored — read from the first row rather than remembered, so a
/// provider swap between requests is visible. `0` when nothing is stored.
ClassMethod StoredWidth() As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT vector FROM sentai_search.StepCorpus")
    If (rs.%SQLCODE < 0) Quit 0
    If 'rs.%Next() Quit 0
    Quit ..WidthOf(rs.%Get("vector"))
}

/// Reads the provider's reason out of a message, so the reason the provider named is the
/// reason the frontend sees.
/// 
/// `EmbeddingService` writes its condition as a leading token on the error text (`slow: …`),
/// which travels through the caught status's text unchanged. A message with no such token is
/// `error`: it is the catch-all, and it is never shown to the operator as a message (FR-024).
/// 
/// The tail is taken with `$PIECE` rather than `$FIND` arithmetic: `$FIND` returns the position
/// just past what it found, and the earlier code added the marker's length to that again, so
/// every token read as `error` — a defect no test had exercised until T018.
ClassMethod ReasonFromMessage(message As %String) As %String
{
    Set tail = $PIECE(message, "Embedding error: ", 2)
    If (tail = "") Quit "error"
    // `NormalizeReason` is the one list of reasons in the product, so this cannot drift from it.
    Quit ##class(sentai.search.SearchOutcome).NormalizeReason($PIECE(tail, ":", 1))
}

}
