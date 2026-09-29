/// Spec 011 T027 / US4: the corpus cannot drift from the catalog. The version stamp follows
/// descriptions and only descriptions (so rewording a label never invalidates stored vectors),
/// a rebuild is idempotent (the same catalog yields the same rows and the same stamp), and rows
/// the catalog does not declare do not survive a rebuild.
/// 
/// The provider row is captured and restored exactly as StepSearchServiceTest does it, because
/// the corpus builds only through the service.
Class sentai.unittest.search.StepCorpusTest Extends sentai.unittest.SentaiTestCase
{

/// The captured row, or "" when there was none. Deliberately %RawString: an object-typed
/// property coerces "" into an oref-shaped value, and "no row at all" — the state CI runs in,
/// with no %Embedding.Config row on the instance — must survive the capture/restore round-trip
/// (found by the T034 gate, 2026-09-28).
Property SavedProvider As %RawString;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Do ##class(sentai.unittest.search.SearchFixtures).ClearCorpus()
    Set ..SavedProvider = ##class(sentai.unittest.search.SearchFixtures).CaptureProvider()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).InstallFakeProvider()
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

/// The catalog as a mutable copy, with one entry's one field replaced — so a test can say
/// "reword this description" or "relabel this entry" without recompiling the catalog, and the
/// version function can be asked about a catalog it was handed rather than the one it reads.
ClassMethod ModifiedCopy(field As %String, type As %String, value As %String) As %DynamicArray
{
    Set copy = ##class(%DynamicArray).%New()
    Set iter = ##class(sentai.registry.StepType).GetCatalog().%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Set row = ##class(%DynamicObject).%New()
        Set row.type = entry.type, row.label = entry.label, row.description = entry.description
        If (entry.type = type) Do row.%Set(field, value)
        Do copy.%Push(row)
    }
    Quit copy
}

/// FR-017 (data-model §2): the stamp is a hash over the catalog's `(type, description)` pairs —
/// so rewording a description changes it, and rewording only a label does not. A label change
/// costs nothing: the stored vectors stay valid and no rebuild is triggered for prose the corpus
/// was never built from.
Method TestVersionFollowsDescriptionsNotLabels()
{
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    Set baseline = ##class(sentai.search.StepSearchService).CorpusVersion(catalog)
    Set reworded = ..ModifiedCopy("description", "switch-journal", "Reworded: roll the journal to a fresh file")
    Set relabeled = ..ModifiedCopy("label", "switch-journal", "Relabelled journal switch")
    Do $$$AssertNotTrue(##class(sentai.search.StepSearchService).CorpusVersion(reworded) = baseline, "a reworded description is a new corpus")
    Do $$$AssertEquals(##class(sentai.search.StepSearchService).CorpusVersion(relabeled), baseline, "a relabelled entry is the same corpus")
}

/// FR-017, R-005: rebuilding is idempotent. The same catalog, embedded twice through the
/// deterministic double, yields the same rows, the same stamp, and the same vectors — so a
/// duplicated concurrent rebuild converges and no lock is needed.
Method TestRebuildingTwiceYieldsTheSameRowsAndVersion()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the first build answers")
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    Set stamp = ##class(sentai.search.StepSearchService).CorpusVersion(catalog)
    &sql(SELECT COUNT(*) INTO :rows1 FROM sentai_search.StepCorpus)
    Set firstText = ..StoredVectorText("custom")

    // Force the one rebuild that matters: a missing row is a stale corpus, so the next search
    // rebuilds — over the remains of the first build, which is the convergence case.
    &sql(DELETE FROM sentai_search.StepCorpus WHERE type = 'custom')
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the rebuild answers")
    &sql(SELECT COUNT(*) INTO :rows2 FROM sentai_search.StepCorpus)
    Do $$$AssertEquals(rows2, rows1, "the rebuild stores the same rows")
    Do $$$AssertEquals(..StoredVectorText("custom"), firstText, "the rebuilt vector is the vector the same catalog always yields")
    // Every row is stamped with the version that was current when it was built, and both builds
    // agree on it.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS stale FROM sentai_search.StepCorpus WHERE corpusVersion <> ?", stamp), stale = 0
    If rs.%Next() Set stale = +rs.%Get("stale")
    Do $$$AssertEquals(stale, 0, "the stamp is the same one both builds wrote")
}

/// FR-017: a row the catalog does not declare does not survive the next build. This is the
/// hermetic spelling of "a type removed from the catalog is deleted from the corpus": the
/// observable is the same — a stored row no catalog entry accounts for is gone after a rebuild —
/// and the test does not recompile the catalog to see it.
Method TestUndeclaredRowDoesNotSurviveARebuild()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the corpus is built first")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO sentai_search.StepCorpus (type, description, vector, corpusVersion, embeddedAt) VALUES ('not-in-catalog', 'foreign row', TO_VECTOR('[1,2,3]'), 'foreign', NOW())")
    Do $$$AssertEquals(rs.%SQLCODE, 0, "the foreign row is stored")

    // The foreign row makes the corpus stale, so the next search rebuilds — and the rebuild is
    // the catalog, nothing else.
    Set outcome = ##class(sentai.search.StepSearchService).Search("journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the search after the rebuild answers")
    &sql(SELECT COUNT(*) INTO :left FROM sentai_search.StepCorpus WHERE type = 'not-in-catalog')
    Do $$$AssertEquals(left, 0, "a row no catalog entry accounts for is deleted by the rebuild")
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    &sql(SELECT COUNT(*) INTO :rows FROM sentai_search.StepCorpus)
    Do $$$AssertEquals(rows, catalog.%Size(), "the rebuilt corpus is exactly the catalog")
}

/// One stored vector's display form, so idempotence can compare vectors rather than only rows.
ClassMethod StoredVectorText(type As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT vector FROM sentai_search.StepCorpus WHERE type = ?", type)
    If 'rs.%Next() Quit ""
    Quit ##class(%Library.Vector).LogicalToDisplay(rs.%Get("vector"))
}

/// Spec 017 T022, FR-007: a stored row carries the identity of the provider that embedded it, and a
/// row without one — every row spec 011 wrote — is not current, so the first search after the
/// upgrade rebuilds once.
Method TestRowsCarryProviderIdentity()
{
    Set outcome = ##class(sentai.search.StepSearchService).Search("rotate the journal")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the corpus is built")
    Set current = ##class(sentai.search.StepSearchService).ProviderIdentity()
    Do $$$AssertTrue(current [ "sentai.unittest.search.FakeEmbeddingService", current)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM sentai_search.StepCorpus WHERE providerIdentity = ?", current)
    Do rs.%Next()
    Do $$$AssertEquals(+rs.%Get("n"), ##class(sentai.registry.StepType).GetCatalog().%Size(), "every row names the provider that embedded it")
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    Do $$$AssertTrue(##class(sentai.search.StepSearchService).CorpusIsCurrent(catalog), "a corpus built by the current provider is current")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE sentai_search.StepCorpus SET providerIdentity = NULL")
    Do $$$AssertNotTrue(##class(sentai.search.StepSearchService).CorpusIsCurrent(catalog), "rows with no identity, as spec 011 wrote them, are not current")
}

}
