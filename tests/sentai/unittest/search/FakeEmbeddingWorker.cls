/// Spec 017 T007: a test-only embedding worker. Everything that is the worker's protocol — the
/// registration, the event, start, stop, liveness — is inherited unchanged from
/// `sentai.search.EmbeddingWorker`; only the model hooks are replaced, so the suite exercises the
/// real protocol with no Python packages and no model on the instance (plan.md design note 5).
/// 
/// Its event and registry names are its own, so a test can never talk to, or stop, a real worker
/// running on the same instance. The knobs a test turns live in `^IRIS.Temp.sentai.embedtest`:
/// `("loadDelay")` and `("encodeDelay")` in seconds, `("failLoad")` to make the load fail.
/// 
/// Test-only by construction: it lives under `tests/`, and nothing in `src/` names it.
Class sentai.unittest.search.FakeEmbeddingWorker Extends sentai.search.EmbeddingWorker
{

Parameter EventName = "sentaiEmbedTest";

Parameter Registry = "^IRIS.Temp.sentai.embedtestreg";

/// The provider class whose row this worker would start for; the fake is only ever started by a
/// test, with an explicit configuration.
Parameter ProviderClass = "sentai.unittest.search.FakeLocalEmbedding";

/// Where the knobs live. Killed by the tests before and after each one.
Parameter Knobs = "^IRIS.Temp.sentai.embedtest";

ClassMethod LoadModel(modelName As %String, cachePath As %String, pythonPath As %String) As %String
{
    Set knobs = ..#Knobs
    Set delay = +$G(@knobs@("loadDelay"))
    If (delay > 0) Hang delay
    If +$G(@knobs@("failLoad")) Quit "load failed: the fake model was told to fail"
    Quit ""
}

ClassMethod Encode(text As %String) As %String
{
    Set knobs = ..#Knobs
    Set delay = +$G(@knobs@("encodeDelay"))
    If (delay > 0) Hang delay
    Quit ##class(%Library.Vector).LogicalToDisplay(##class(sentai.unittest.search.FakeEmbeddingService).Of(text))
}

/// "missing" is the one model name the fake says is not in the cache, so `IsValidConfig`'s
/// rejection path is exercised without touching the file system.
ClassMethod CheckModel(config As %DynamicObject) As %String
{
    If (config.%Get("modelName") = "missing") Quit "model missing is not in "_config.%Get("cachePath")
    Quit ""
}

/// Clears every knob, so each test starts from a worker that loads and answers at once.
ClassMethod ResetKnobs()
{
    Set knobs = ..#Knobs
    Kill @knobs
}

ClassMethod SetKnob(name As %String, value)
{
    Set knobs = ..#Knobs
    Set @knobs@(name) = value
}

}
