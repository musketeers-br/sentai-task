/// Spec 011 T009 / US1: ranking over the closed catalog through the deterministic
/// FakeEmbeddingService, so a specific ordering is assertable with no network and no model.
/// Written before `sentai.search.StepSearchService` existed (Principle V).
Class sentai.unittest.search.StepSearchServiceTest Extends sentai.unittest.SentaiTestCase
{

/// The platform row that was configured before this test, so `OnAfterOneTest` can put it back.
/// `""` means there was none. The capture, the double and the restore live in `SearchFixtures`,
/// because the REST test needs the same three steps and two copies of a restore that has to work
/// would eventually be one that doesn't.
/// The captured row, or "" when there was none. Deliberately %RawString: an object-typed
/// property coerces "" into an oref-shaped value, and "no row at all" — the state CI runs in,
/// with no %Embedding.Config row on the instance — must survive the capture/restore round-trip
/// (found by the T034 gate, 2026-09-28).
Property SavedProvider As %RawString;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).ClearCorpus()
    Do $$$AssertEquals(problem, "", "the corpus starts empty")
    Set ..SavedProvider = ##class(sentai.unittest.search.SearchFixtures).CaptureProvider()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).InstallFakeProvider()
    // Asserted here rather than inside the fixture: `$$$AssertTrue` is an instance macro, and a
    // double that failed to install would otherwise make every assertion below meaningless.
    Do $$$AssertEquals(problem, "", "the test double is installed as the configured provider row")
    Quit sc
}

Method OnAfterOneTest() As %Status
{
    Set sc = ##super()
    Do ##class(sentai.unittest.search.SearchFixtures).ClearCorpus()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).RestorePlatformProvider(..SavedProvider)
    Do $$$AssertEquals(problem, "", "the platform's own provider row is put back")
    Quit sc
}

/// FR-001, SC-001: the ranking the operator sees is ordered by descending score. The floor is
/// applied inside the service, so the first match is already the best one above it.
///
/// The query is chosen because the double answers it with several entries above the floor. A
/// one-match ranking would satisfy a descending-order assertion without ever comparing two, so the
/// test states that it has something to compare.
Method TestRankingIsOrderedByDescendingScore()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("check globals and reclaim space")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the provider is installed, so the search is answered")
    Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
    Do $$$AssertTrue(matches.%Size() > 1, "the ranking has more than one entry, so the order is compared")
    Set howMany = matches.%Size(), previous = "", i = 0
    For i = 0:1:(howMany - 1) {
        Set score = matches.%Get(i).score
        If (previous '= "") {
            Do $$$AssertTrue(score <= previous, "score "_(howMany - i)_" is not above the one before it")
        }
        Set previous = score
    }
}

/// FR-008: a query that is not close to anything is `available: true` with **no** matches.
/// An empty ranking is an answer; it is not the degraded shape, and the two are never confused.
/// The query is punctuation only, so the test double has no word to put in a bucket.
Method TestBelowFloorQueryIsAvailableWithNoMatches()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("???")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "no match is still an answer")
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).Matches(outcome).%Size(), 0)
}

/// Two entries with the same vector score identically, so only catalog order can separate them
/// (R-008: the floor is absolute, and a tie is not a reason to invent a ranking).
Method TestTiesKeepCatalogOrder()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("Merge each global's data blocks to reclaim unused space")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome))
    // Make two entries score identically by giving one the other's vector. The corpus is now
    // non-empty and current, so a later Search must not rebuild over this fixture.
    &sql(UPDATE sentai_search.StepCorpus SET vector =
        (SELECT source.vector FROM sentai_search.StepCorpus source WHERE source.type = 'compact-globals')
        WHERE type = 'storage-headroom-check')
    Set outcome = ##class(sentai.search.StepSearchService).Search("Merge each global's data blocks to reclaim unused space")
    Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
    Set firstAt = -1, secondAt = -1, i = 0
    For i = 0:1:(matches.%Size() - 1) {
        Set type = matches.%Get(i).type
        If (type = "compact-globals") Set firstAt = i
        If (type = "storage-headroom-check") Set secondAt = i
    }
    Do $$$AssertTrue(firstAt >= 0, "the tied entry that comes first in the catalog is in the ranking")
    Do $$$AssertTrue(secondAt >= 0, "both tied entries are in the ranking")
    Do $$$AssertEquals(matches.%Get(firstAt).score, matches.%Get(secondAt).score, "they really are tied")
    Do $$$AssertTrue(firstAt < secondAt, "a tie is broken by catalog order, not by hash or insertion order")
}

/// FR-013, R-009, R-011: nothing outside the closed catalog can come back out of a ranking.
/// The type is the only thing that crosses the wire, so an entry the catalog does not name has
/// nothing the palette could render.
Method TestEveryReturnedTypeComesFromTheCatalog()
{
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    // Each of these answers with at least one entry, so the membership check has rows to check. A
    // query that matched nothing would satisfy it without proving anything.
    For query = "free up disk space", "rotate the journal", "space", "check my globals are sound", "check globals and reclaim space" {
        Set outcome = ##class(sentai.search.StepSearchService).Search(query)
        Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), query)
        Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
        Do $$$AssertTrue(matches.%Size() > 0, "the query matched something to check ("_query_")")
        Set i = 0
        For i = 0:1:(matches.%Size() - 1) {
            Do $$$AssertTrue(matches.%Get(i).type '= "", "a match always names a type ("_query_")")
            Do $$$AssertNotTrue(##class(sentai.registry.StepType).Lookup(matches.%Get(i).type) = "", "every type is in the catalog ("_query_")")
        }
    }
    Do $$$AssertTrue(catalog.%Size() > 0, "the catalog the assertion checks against is not empty")
}

/// R-004, R-005: the corpus is stored rather than recomputed per request, and it holds exactly
/// one row per catalog entry — no more, and none missing.
Method TestCorpusHoldsOneRowPerCatalogEntry()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the corpus is built on demand")
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    &sql(SELECT COUNT(*) INTO :rows FROM sentai_search.StepCorpus)
    Do $$$AssertEquals(rows, catalog.%Size())
    &sql(SELECT COUNT(DISTINCT type) INTO :distinctTypes FROM sentai_search.StepCorpus)
    Do $$$AssertEquals(distinctTypes, catalog.%Size(), "one row per type, never a duplicate")
    Set version = ##class(sentai.search.StepSearchService).CorpusVersion(##class(sentai.registry.StepType).GetCatalog())
    // A bound statement rather than `&sql` with a bare local in the WHERE clause: that form does
    // not bind here and leaves the count undefined, which would fail as a wrong number rather
    // than as a wrong statement (R-014).
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS stale FROM sentai_search.StepCorpus WHERE corpusVersion <> ?", version), stale = 0
    If rs.%Next() Set stale = +rs.%Get("stale")
    Do $$$AssertEquals(stale, 0, "every row is stamped with the version that was current when it was built")
}

/// FR-024 / SC-004: with no provider row, the answer is the `not-configured` reason on a 200,
/// not an exception and not a 5xx. The corpus may be built or not; the shape is the assertion.
/// `OnAfterOneTest` puts the platform's own row back, so removing it here is enough.
Method TestWithoutAProviderRowSearchIsUnavailableNotConfigured()
{
    Do ##class(sentai.unittest.search.SearchFixtures).RemoveProvider()
    Set outcome = ##class(sentai.search.StepSearchService).Search("free up disk space")
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome))
    Do $$$AssertEquals(outcome.reason, "not-configured")
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "an unavailable outcome carries no matches key (FR-025)")
}

/// FR-024: a row pointing at a host that refuses connections is the `unreachable` reason. The
/// origin is loopback port 1, which nothing listens on in the container, so the refusal is
/// immediate and does not depend on DNS (a slow resolver could otherwise flip this into the
/// connect-budget branch). The corpus is empty, so the refusal happens while building it: the
/// service must answer with the reason and never leave a partial corpus behind (Constitution
/// IV, FR-025) — a provider's status is never allowed to cross as an exception either.
Method TestUnreachableProviderIsUnavailableUnreachable()
{
    Do ##class(sentai.unittest.search.SearchFixtures).RemoveProvider()
    // Built as an object, not a literal: the table validates the column as strict JSON (R-014).
    Set cfg = ##class(%DynamicObject).%New()
    Do cfg.%Set("host", "127.0.0.1"), cfg.%Set("port", 1), cfg.%Set("https", 0)
    Do cfg.%Set("path", "/v1/embeddings"), cfg.%Set("model", "probe-model")
    Set problem = ##class(sentai.unittest.search.SearchFixtures).WriteProvider("sentai-steps", "sentai.search.EmbeddingService", cfg.%ToJSON(), 256, "unreachable probe")
    Do $$$AssertEquals(problem, "", "the refused-origin row installs")
    Set outcome = ##class(sentai.search.StepSearchService).Search("free up disk space")
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome))
    Do $$$AssertEquals(outcome.reason, "unreachable")
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "an unavailable outcome carries no matches key (FR-025)")
    Do $$$AssertEquals(##class(sentai.unittest.search.SearchFixtures).CorpusRowCount(), 0, "a failed build leaves no partial corpus behind")
}

/// FR-024: a provider past its whole-response budget is the `slow` reason. The double throws
/// exactly the status `sentai.search.EmbeddingService` throws in that condition — the same
/// #10200 with the same leading `slow:` token — so the service's reason mapping is asserted
/// end to end without making the suite wait out a real timeout.
Method TestSlowProviderIsUnavailableSlow()
{
    Do ##class(sentai.unittest.search.SearchFixtures).RemoveProvider()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).WriteProvider("sentai-steps", "sentai.unittest.search.SlowEmbeddingService", ##class(sentai.unittest.search.SearchFixtures).DoubleConfiguration(), 256, "slow probe")
    Do $$$AssertEquals(problem, "", "the slow double installs")
    Set outcome = ##class(sentai.search.StepSearchService).Search("free up disk space")
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome))
    Do $$$AssertEquals(outcome.reason, "slow")
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "an unavailable outcome carries no matches key (FR-025)")
}

/// FR-024: a provider whose vectors are a different width than the stored corpus is the
/// `incompatible` reason — never an empty ranking, which would look like "no results" and is
/// exactly the masquerade FR-023 forbids. Measured: VECTOR_COSINE across widths fails no
/// statement at all, it simply yields no score, so a service that did not compare widths would
/// answer `available` with nothing in it. The corpus is built by the standard 256-bucket
/// double, then the row is re-pointed at the half-width double without touching the corpus —
/// the provider swap the story describes.
Method TestIncompatibleProviderIsUnavailableIncompatible()
{
    // The standard double from OnBeforeOneTest builds a 256-wide corpus.
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the corpus is built before the provider is swapped")
    Do ##class(sentai.unittest.search.SearchFixtures).RemoveProvider()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).WriteProvider("sentai-steps", "sentai.unittest.search.NarrowEmbeddingService", ##class(sentai.unittest.search.SearchFixtures).DoubleConfiguration(), 128, "narrow probe")
    Do $$$AssertEquals(problem, "", "the half-width double installs")
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "a width mismatch is never a ranking")
    Do $$$AssertEquals(outcome.reason, "incompatible")
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "an unavailable outcome carries no matches key (FR-025)")
}

/// FR-018, R-009: a class name is not a search key. The corpus is built from descriptions, so a
/// query spelled as an implementation class name — including the product's own `%SYS.Task.*`
/// names and the `sentai.steps.*` ones — may only ever surface entries the catalog already
/// declares, and never an entry the catalog does not name. This is the closed-set claim made
/// structurally, with the strongest spelling a query can take.
Method TestClassNamesAreNotSearchKeys()
{
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    Do $$$AssertTrue(catalog.%Size() > 0)
    For query = "%SYS.Task.IntegrityCheck", "%SYS.Task.PurgeAudit", "sentai.steps.StorageHeadroomCheck", "PurgeTaskHistory" {
        Set outcome = ##class(sentai.search.StepSearchService).Search(query)
        Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "a class-name query is still an answer ("_query_")")
        Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
        Set i = 0
        For i = 0:1:(matches.%Size() - 1) {
            Do $$$AssertNotTrue(##class(sentai.registry.StepType).Lookup(matches.%Get(i).type) = "", "a class-name query cannot surface anything outside the catalog ("_query_")")
        }
    }
}

/// FR-018: the corpus row for the legacy `custom` entry is derived from its `description`. That
/// entry is the sharpest test of the constraint: its `class` is empty, so a ranking that offers
/// it can only have come from its prose — a builder that read `class` anywhere on this path
/// would embed empty text for it and it could never surface at all.
Method TestCorpusRowIsDerivedFromTheDescription()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the corpus is built first")
    Set customDescription = ""
    Set iter = ##class(sentai.registry.StepType).GetCatalog().%GetIterator()
    While iter.%GetNext(.key, .entry) {
        If (entry.type = "custom") Set customDescription = entry.description
    }
    Do $$$AssertTrue($L(customDescription) > 0, "the catalog declares prose for the legacy entry")
    Set stored = ""
    &sql(SELECT description INTO :stored FROM sentai_search.StepCorpus WHERE type = 'custom')
    Do $$$AssertEquals(stored, customDescription, "the stored row is the catalog's own prose")
    // Searching that prose's own words must offer the entry, which an empty-`class` text could
    // never do — the description is what the vector was embedded from.
    Set outcome = ##class(sentai.search.StepSearchService).Search("placeholder for an operator-declared class")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome))
    Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
    Set foundAt = -1, i = 0
    For i = 0:1:(matches.%Size() - 1) {
        If (matches.%Get(i).type = "custom") Set foundAt = i
    }
    Do $$$AssertTrue(foundAt >= 0, "the legacy entry is findable by its description's words")
}

/// FR-013: a query for a capability the product does not declare can never conjure an entry for
/// it. One query below shares a word with real descriptions (so the membership check has rows to
/// check) and one shares none (so the empty ranking is the answer, FR-008) — in both cases
/// everything offered is declared, and nothing else is.
Method TestUndeclaredCapabilityYieldsNoUndeclaredEntry()
{
    For query = "teleport the database to the moon", "brew coffee and refill the toner" {
        Set outcome = ##class(sentai.search.StepSearchService).Search(query)
        Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "an undeclared capability is an answer, never an error ("_query_")")
        Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
        Set i = 0
        For i = 0:1:(matches.%Size() - 1) {
            Do $$$AssertNotTrue(##class(sentai.registry.StepType).Lookup(matches.%Get(i).type) = "", "only declared capabilities are ever offered ("_query_")")
        }
    }
}

}
