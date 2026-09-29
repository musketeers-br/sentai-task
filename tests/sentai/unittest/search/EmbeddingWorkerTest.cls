/// Spec 017 T009: the one process that holds the model (research R-1, R-2, data-model §4).
/// 
/// Driven through `FakeEmbeddingWorker`, which inherits the whole protocol and replaces only the
/// model, so what is asserted here is the real registration, event and lifecycle code.
Class sentai.unittest.search.EmbeddingWorkerTest Extends sentai.unittest.SentaiTestCase
{

Parameter Worker = "sentai.unittest.search.FakeEmbeddingWorker";

/// Seconds a test waits for a state before it gives up. Generous: the fake loads at once unless a
/// test asks for a delay, so a pass never waits this long.
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
    Set cfg = ##class(%DynamicObject).%New()
    Do cfg.%Set("modelName", model)
    Do cfg.%Set("cachePath", "/tmp")
    Quit cfg.%ToJSON()
}

/// FR-004a: a started worker reports `warming` while it loads and `ready` once it has, with the
/// pid and the model it loaded registered where callers read them.
Method TestRegistrationGoesWarmingThenReady()
{
    Set worker = ..#Worker
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).SetKnob("loadDelay", 1)
    Set cfg = ..Config()
    Do $$$AssertStatusOK($CLASSMETHOD(worker, "Start", cfg))
    Do $$$AssertEquals($CLASSMETHOD(worker, "State"), "warming", "a worker still loading is warming")
    Do $$$AssertTrue($CLASSMETHOD(worker, "WaitUntil", "ready", ..#Patience), "the worker becomes ready")
    Do $$$AssertEquals($CLASSMETHOD(worker, "LoadedKey"), $CLASSMETHOD(worker, "ModelKey", cfg), "the registration names the model the worker loaded")
    Set node = $CLASSMETHOD(worker, "Registry")
    Do $$$AssertTrue($DATA(^$JOB(+$G(@node@("pid")))), "the registered pid is a live process")
}

/// R-2: starting is idempotent — a second `Start` for the same model leaves the one worker there.
Method TestStartIsIdempotent()
{
    Set worker = ..#Worker, cfg = ..Config()
    Do $$$AssertStatusOK($CLASSMETHOD(worker, "Start", cfg))
    Do $$$AssertTrue($CLASSMETHOD(worker, "WaitUntil", "ready", ..#Patience), "the worker becomes ready")
    Set node = $CLASSMETHOD(worker, "Registry"), pid = $G(@node@("pid"))
    Do $$$AssertStatusOK($CLASSMETHOD(worker, "Start", cfg))
    Do $$$AssertEquals($G(@node@("pid")), pid, "the second start did not replace the worker")
    Do $$$AssertEquals($CLASSMETHOD(worker, "State"), "ready")
}

/// A ready worker answers a text with the vector's display form.
Method TestReadyWorkerAnswers()
{
    Set worker = ..#Worker
    Do $CLASSMETHOD(worker, "Start", ..Config())
    Do $$$AssertTrue($CLASSMETHOD(worker, "WaitUntil", "ready", ..#Patience), "the worker becomes ready")
    Set reason = ""
    Set vector = $CLASSMETHOD(worker, "Ask", "rotate the journal", 2, .reason)
    Do $$$AssertEquals(reason, "", "a ready worker answers")
    Do $$$AssertEquals($LENGTH(vector, ","), 256, "the double's width")
}

/// `Stop` ends the worker and leaves neither a registration nor an event behind.
Method TestStopRemovesTheWorker()
{
    Set worker = ..#Worker
    Do $CLASSMETHOD(worker, "Start", ..Config())
    Do $$$AssertTrue($CLASSMETHOD(worker, "WaitUntil", "ready", ..#Patience), "the worker becomes ready")
    Do $$$AssertStatusOK($CLASSMETHOD(worker, "Stop"))
    Do $$$AssertEquals($CLASSMETHOD(worker, "State"), "none")
    Do $$$AssertNotTrue($SYSTEM.Event.Defined($CLASSMETHOD(worker, "Event")), "the event is deleted")
    Set node = $CLASSMETHOD(worker, "Registry")
    Do $$$AssertNotTrue($DATA(@node), "the registration is removed")
}

/// A registration whose process is gone — the instance restarted, the process was killed — is not
/// a worker: callers must see `none` and start a new one, never wait on a dead pid.
Method TestDeadPidReadsAsAbsent()
{
    Set worker = ..#Worker, node = $CLASSMETHOD(worker, "Registry")
    Set @node@("pid") = 99999999, @node@("state") = "ready", @node@("key") = $CLASSMETHOD(worker, "ModelKey", ..Config())
    Do $$$AssertEquals($CLASSMETHOD(worker, "State"), "none")
    Kill @node
}

/// A model that cannot load is `failed`, with the reason kept for the caller, and the worker does
/// not stay behind holding nothing.
Method TestFailedLoadIsFailed()
{
    Set worker = ..#Worker
    Do ##class(sentai.unittest.search.FakeEmbeddingWorker).SetKnob("failLoad", 1)
    Do $CLASSMETHOD(worker, "Start", ..Config())
    Do $$$AssertTrue($CLASSMETHOD(worker, "WaitUntil", "failed", ..#Patience), "the worker reports the failure")
    Do $$$AssertTrue($CLASSMETHOD(worker, "LastError") [ "told to fail", "the load's own reason is kept")
    Do $$$AssertNotTrue($SYSTEM.Event.Defined($CLASSMETHOD(worker, "Event")), "a failed worker leaves no event")
}

}
