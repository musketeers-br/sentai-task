/// Spec 017: the in-process embedding provider — what the `sentai-steps` row names on the dev and
/// demo images (data-model §1). The model is `sentence-transformers`, run inside the instance, so
/// the stack needs no similarity service of its own and the operator's query never leaves it.
/// 
/// This class never loads the model. It asks the one process that holds it,
/// `sentai.search.EmbeddingWorker`, and turns every condition of that process into the reason token
/// `StepSearchService.ReasonFromMessage` already reads (Constitution IV):
/// 
///   no worker, or a dead one          start it, then `warming`   (FR-004a: never wait for a load)
///   loading                           `warming`
///   holding another model             replace it, then `warming` (a model is never answered by
///                                     the wrong one)
///   failed to load this model         `error`                    (not restarted on every keystroke)
///   ready but no answer within 0.8 s  `slow`                     (the request stays under FR-004's 1 s)
/// 
/// `Configuration` keys: `modelName` and `cachePath` (required), `pythonPath` (optional extra
/// import path). Nothing else about the provider is written in code (FR-002).
Class sentai.search.LocalEmbedding Extends %Embedding.Interface
{

/// The worker this provider asks. A compile-time parameter — never a name read from input
/// (Constitution II); the test double's subclass is the only other value it ever has.
Parameter WorkerClass = "sentai.search.EmbeddingWorker";

/// Seconds to wait for a ready worker's answer. Measured answers take ≈12 ms (research R-1), so
/// this only ever fires when the worker is stuck, and it keeps the request inside one second.
Parameter AskTimeout = 0.8;

/// Called by `%Embedding.Config`'s validating trigger, so a row that cannot work is rejected at
/// insert time with a message rather than at the operator's first keystroke.
ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean
{
    Set errorMsg = ""
    If ('$IsObject(config)) || ($L(config.%Get("modelName")) = 0) {
        Set errorMsg = "modelName not set"
        Quit 0
    }
    If ($L(config.%Get("cachePath")) = 0) {
        Set errorMsg = "cachePath not set"
        Quit 0
    }
    Set problem = $CLASSMETHOD(..Worker(), "CheckModel", config)
    If (problem '= "") {
        Set errorMsg = problem
        Quit 0
    }
    Quit 1
}

/// The platform's entry point: the vector of `input` under the row's `configuration`.
ClassMethod Embedding(input As %String, configuration As %String) As %Vector
{
    Set text = $S($IsObject(input):input.%ToJSON(), 1:input)
    Set worker = ..Worker()
    Set key = $CLASSMETHOD(worker, "ModelKey", configuration)
    Set state = $CLASSMETHOD(worker, "State")
    Set heldKey = $CLASSMETHOD(worker, "LoadedKey")

    If (state = "none") {
        Do $CLASSMETHOD(worker, "Start", configuration)
        Do ..Fail("warming", "the model is loading")
    }
    If (heldKey '= key) {
        Do $CLASSMETHOD(worker, "Start", configuration)
        Do ..Fail("warming", "the configured model changed; loading it")
    }
    If (state = "failed") Do ..Fail("error", $CLASSMETHOD(worker, "LastError"))
    If (state = "warming") Do ..Fail("warming", "the model is loading")

    Set reason = ""
    Set vector = $CLASSMETHOD(worker, "Ask", text, ..#AskTimeout, .reason)
    If (reason '= "") Do ..Fail(reason, "the embedding worker did not answer")
    Quit ##class(%Library.Vector).DisplayToLogical(vector)
}

/// The worker class of this provider, read from the class actually called so a subclass's
/// parameter is the one used.
ClassMethod Worker() As %String
{
    Quit $PARAMETER($CLASSNAME(), "WorkerClass")
}

/// Throws the platform's embedding error with `reason` as the leading token, the shape
/// `EmbeddingService` uses and `StepSearchService.ReasonFromMessage` parses.
ClassMethod Fail(reason As %String, detail As %String)
{
    $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, reason_": "_detail))
}

}
