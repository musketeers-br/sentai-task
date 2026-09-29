/// Provider and corpus fixtures for the semantic-search tests (spec 011).
///
/// The double is installed under **the name the service reads**, not under a name of its own. The
/// service looks up one fixed row, so a double registered beside it would never be called and the
/// tests would quietly measure the real provider instead. The platform's own row is captured before
/// and written back afterwards, because a dev stack really does carry an Ollama row here and a suite
/// that left a double behind would change how the instance behaves for the operator.
///
/// Returns are `""` on success and the SQL message on failure, because the assertion macros are
/// instance methods on the test class and cannot be called from here (R-014).
Class sentai.unittest.search.SearchFixtures Extends %RegisteredObject
{

/// The row the service reads. Named here once so a test cannot install a double under a different
/// name by accident and measure nothing at all.
Parameter ProviderName = "sentai-steps";

/// The double: deterministic, 256 dimensions, no network and no model.
Parameter DoubleClass = "sentai.unittest.search.FakeEmbeddingService";
Parameter DoubleLength = 256;

/// Reads the configured row, if any, as an object this class can hand back later.
ClassMethod CaptureProvider(name As %String = "sentai-steps") As %DynamicObject
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EmbeddingClass, Configuration, VectorLength, Description FROM %EMBEDDING.Config WHERE Name = ?", name)
    If 'rs.%Next() Quit ""
    Set saved = ##class(%DynamicObject).%New()
    Set saved.class = rs.%Get("EmbeddingClass"), saved.configuration = rs.%Get("Configuration")
    Set saved.vectorLength = +rs.%Get("VectorLength"), saved.description = rs.%Get("Description")
    Quit saved
}

ClassMethod WriteProvider(name As %String, className As %String, configuration As %String, vectorLength As %Integer, description As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO %EMBEDDING.Config (Name, EmbeddingClass, Configuration, VectorLength, Description) VALUES (?, ?, ?, ?, ?)", name, className, configuration, vectorLength, description)
    If (rs.%SQLCODE < 0) Quit rs.%Message
    Quit ""
}

/// Bound parameters, not `&sql` with a bare local: that form does not bind on this build, so the
/// delete would quietly do nothing and the next insert would collide on the primary key (R-014).
ClassMethod RemoveProvider(name As %String = "sentai-steps")
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM %EMBEDDING.Config WHERE Name = ?", name)
}

/// The configuration the double is installed with, as the platform will accept it.
///
/// Built as an object rather than written as an ObjectScript literal: `%EMBEDDING.Config` validates
/// the column on insert and rejects anything that is not strict JSON, so a single-quoted pseudo-JSON
/// literal fails with SQLCODE -415 at insert time rather than at read time (R-014).
ClassMethod DoubleConfiguration() As %String
{
    Set cfg = ##class(%DynamicObject).%New()
    Do cfg.%Set("host", "test")
    Do cfg.%Set("port", 1)
    Do cfg.%Set("https", 0)
    Do cfg.%Set("path", "/v1/embeddings")
    Do cfg.%Set("model", "all-minilm")
    Quit cfg.%ToJSON()
}

ClassMethod InstallFakeProvider() As %String
{
    Do ..RemoveProvider(..#ProviderName)
    Quit ..WriteProvider(..#ProviderName, ..#DoubleClass, ..DoubleConfiguration(), ..#DoubleLength, "deterministic test double")
}

ClassMethod RestorePlatformProvider(saved As %DynamicObject) As %String
{
    Do ..RemoveProvider(..#ProviderName)
    If saved = "" Quit ""
    Quit ..WriteProvider(..#ProviderName, saved.class, saved.configuration, saved.vectorLength, saved.description)
}

/// Every test starts from an empty corpus, so a lazily built corpus is rebuilt for that test rather
/// than inherited from the one before it.
ClassMethod ClearCorpus() As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM sentai_search.StepCorpus")
    If (rs.%SQLCODE < 0) Quit rs.%Message
    Quit ""
}

/// How many corpus rows are stored. The observable that tells a reached service from a request the
/// Dispatcher refused: a service that is called with a real `q` builds the corpus, so a count that
/// does not move is proof nothing downstream ran.
///
/// The column is aliased `n`, not `rows`: `ROWS` is a reserved word and the statement is rejected
/// with it, which would make this read `0` forever and quietly pass the assertion it is there to
/// falsify (R-014).
ClassMethod CorpusRowCount() As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM sentai_search.StepCorpus")
    Set count = 0
    If rs.%Next() Set count = +rs.%Get("n")
    Quit count
}

}
