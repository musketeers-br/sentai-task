/// Spec 017 T010: the in-process provider as the platform calls it — `IsValidConfig` from the
/// configuration table's trigger and `Embedding` from search — turning every worker condition into
/// the reason token `StepSearchService.ReasonFromMessage` reads (FR-004a, FR-012, research R-2).
/// 
/// Driven through `FakeLocalEmbedding`, which differs from the real class only in the worker it
/// names, so the reason mapping asserted here is the shipped code.
Class sentai.unittest.search.LocalEmbeddingTest Extends sentai.unittest.SentaiTestCase
{

Parameter Provider = "sentai.unittest.search.FakeLocalEmbedding";

Parameter Worker = "sentai.unittest.search.FakeEmbeddingWorker";

Parameter Patience = 10;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).Stop()
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).ResetKnobs()
    Quit sc
}

Method OnAfterOneTest() As %Status
{
    Set sc = ##super()
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).Stop()
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).ResetKnobs()
    Quit sc
}

ClassMethod Config(model As %String = "fake-a") As %String
{
    Quit ##class(sentai.unittest.search.EmbeddingWorkerTest).Config(model)
}

/// The text of what `Embedding` threw, or "" when it returned a vector. The reason is the leading
/// token after "Embedding error: ", the same text the search service parses.
ClassMethod Thrown(text As %String, configuration As %String) As %String
{
    Set problem = ""
    Try {
        Set vector = $CLASSMETHOD(..#Provider, "Embedding", text, configuration)
    } Catch e {
        Set problem = ##class(%SYSTEM.Status).GetErrorText(e.AsStatus())
    }
    Quit problem
}

ClassMethod ReasonOf(problem As %String) As %String
{
    Quit ##class(sentai.search.StepSearchService).ReasonFromMessage(problem)
}

/// A row must say which model and where it is cached; anything else is rejected at insert time
/// with a message, never at the operator's first keystroke.
Method TestConfigNeedsModelAndCache()
{
    Set provider = ..#Provider, msg = ""
    Do $$$AssertNotTrue($CLASSMETHOD(provider, "IsValidConfig", {"cachePath": "/tmp"}, .msg), "no modelName")
    Do $$$AssertTrue(msg [ "modelName", msg)
    Set msg = ""
    Do $$$AssertNotTrue($CLASSMETHOD(provider, "IsValidConfig", {"modelName": "fake-a"}, .msg), "no cachePath")
    Do $$$AssertTrue(msg [ "cachePath", msg)
    Set msg = ""
    Do $$$AssertNotTrue($CLASSMETHOD(provider, "IsValidConfig", {"modelName": "missing", "cachePath": "/tmp"}, .msg), "model not in the cache")
    Do $$$AssertTrue(msg [ "not in", msg)
    Set msg = ""
    Do $$$AssertTrue($CLASSMETHOD(provider, "IsValidConfig", {"modelName": "fake-a", "cachePath": "/tmp"}, .msg), msg)
}

/// FR-004a: with no worker, the first call starts one and answers `warming` at once — it never
/// waits for the load.
Method TestFirstCallStartsWorkerAndIsWarming()
{
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).SetKnob("loadDelay", 1)
    Set problem = ..Thrown("free up disk space", ..Config())
    Do $$$AssertEquals(..ReasonOf(problem), "warming", problem)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "ready", ..#Patience), "the call started a worker, which becomes ready")
}

/// A ready worker's answer is returned as a vector.
Method TestReadyWorkerAnswersVector()
{
    Set cfg = ..Config()
    Do $CLASSMETHOD(..#Worker, "Start", cfg)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "ready", ..#Patience), "ready")
    Set vector = $CLASSMETHOD(..#Provider, "Embedding", "rotate the journal", cfg)
    Do $$$AssertEquals($LENGTH(##class(%Library.Vector).LogicalToDisplay(vector), ","), 256, "the double's width")
}

/// A ready worker that does not answer within the caller's budget is `slow`, so the whole request
/// stays inside FR-004's one second.
Method TestSlowWorkerIsSlow()
{
    Set cfg = ..Config()
    Do $CLASSMETHOD(..#Worker, "Start", cfg)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "ready", ..#Patience), "ready")
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).SetKnob("encodeDelay", 1.5)
    Set problem = ..Thrown("rotate the journal", cfg)
    Do $$$AssertEquals(..ReasonOf(problem), "slow", problem)
}

/// A registered worker whose process is gone is started again, and the caller is told `warming`.
Method TestDeadWorkerIsRestarted()
{
    Set cfg = ..Config(), node = $CLASSMETHOD(..#Worker, "Registry")
    Set @node@("pid") = 99999999, @node@("state") = "ready", @node@("key") = $CLASSMETHOD(..#Worker, "ModelKey", cfg)
    Set problem = ..Thrown("rotate the journal", cfg)
    Do $$$AssertEquals(..ReasonOf(problem), "warming", problem)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "ready", ..#Patience), "a new worker becomes ready")
    Do $$$AssertNotTrue(+$G(@node@("pid")) = 99999999, "the dead pid is no longer registered")
}

/// The row now names another model: the worker holding the old one is replaced, and until the new
/// one is ready the caller is told `warming` rather than answered by the wrong model.
Method TestModelChangeRestartsWorker()
{
    Set a = ..Config("fake-a"), b = ..Config("fake-b")
    Do $CLASSMETHOD(..#Worker, "Start", a)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "ready", ..#Patience), "model a ready")
    Set problem = ..Thrown("rotate the journal", b)
    Do $$$AssertEquals(..ReasonOf(problem), "warming", problem)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "ready", ..#Patience), "model b ready")
    Do $$$AssertEquals($CLASSMETHOD(..#Worker, "LoadedKey"), $CLASSMETHOD(..#Worker, "ModelKey", b), "the worker now holds model b")
}

/// A model that failed to load is `error` for that model — the provider does not restart it on
/// every keystroke.
Method TestFailedLoadIsError()
{
    Set cfg = ..Config()
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).SetKnob("failLoad", 1)
    Do $CLASSMETHOD(..#Worker, "Start", cfg)
    Do $$$AssertTrue($CLASSMETHOD(..#Worker, "WaitUntil", "failed", ..#Patience), "the load failed")
    Set problem = ..Thrown("rotate the journal", cfg)
    Do $$$AssertEquals(..ReasonOf(problem), "error", problem)
}

}
