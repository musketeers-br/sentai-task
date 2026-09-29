/// Spec 017: the one process that holds the embedding model for in-process step-type search.
/// 
/// Loading `sentence-transformers` and the model costs about ten seconds and 500 MB in a process
/// (research R-1, measured). Paying that in every CSP gateway worker would put a ten-second load on
/// an operator's keystroke whenever the gateway starts a new one, and multiply the memory. So the
/// model lives here, once, and callers ask for a vector over a named `$SYSTEM.Event` resource
/// (≈12 ms round trip). `sentai.search.LocalEmbedding` is the only caller in the product.
/// 
/// The registration lives in an IRISTEMP global (`^IRIS.Temp…`), so a restart can never leave a
/// claim to a worker that is gone, and liveness is always confirmed from the pid rather than
/// trusted from the global. Everything is subscripted by namespace, so two namespaces running the
/// module keep two workers.
/// 
/// Registration, per namespace (data-model §4):
///   ("pid")  the worker's `$JOB`         ("state") "warming" | "ready" | "failed"
///   ("key")  the model it holds          ("error") why it failed, when it did
///   ("startedAt"), ("readyAt")           `$ZTIMESTAMP`s, diagnostic only
/// 
/// ObjectScript owns the process, the event, the registration and every failure; Python does the
/// two things only Python can: load the model and encode a text (`LoadModel`, `Encode`, `CheckModel`).
/// A subclass may replace those three hooks — the test double does — and nothing else.
Class sentai.search.EmbeddingWorker Extends %RegisteredObject
{

/// The event the worker listens on; the namespace is appended. IRIS resource names take letters and
/// digits only — `-`, `_` or `.` fail with `<FUNCTION>` — and at most 32 characters, so the
/// namespace is stripped of punctuation and the whole name cut to 32 (see `Event`).
Parameter EventName = "sentaiEmbed";

/// The registration global; the namespace is its first subscript.
Parameter Registry = "^IRIS.Temp.sentai.embed";

/// The configuration row a start with no configuration reads, and the provider class it must name
/// for the worker to be worth starting (a row that names the HTTP provider needs no model here).
Parameter ConfigName = "sentai-steps";

Parameter ProviderClass = "sentai.search.LocalEmbedding";

/// Seconds `Stop` waits for the worker to exit before it clears the registration anyway.
Parameter StopWait = 5;

/// The message a stop request carries in place of a caller's pid.
Parameter StopCaller = 0;

/// The registration node for this namespace, as a global reference usable with `@`.
/// 
/// Read through `$PARAMETER($CLASSNAME(), …)` rather than `..#Registry`, so a subclass's own
/// parameters are the ones used when its inherited methods run.
ClassMethod Registry() As %String
{
    Set global = $PARAMETER($CLASSNAME(), "Registry")
    Quit $NAME(@global@($NAMESPACE))
}

/// The event resource name for this namespace: letters and digits only, at most 32 characters.
ClassMethod Event() As %String
{
    Quit $EXTRACT($PARAMETER($CLASSNAME(), "EventName")_$ZSTRIP($NAMESPACE, "*P"), 1, 32)
}

/// What identifies the model a configuration asks for. A worker holding another key is replaced.
ClassMethod ModelKey(configuration As %String) As %String
{
    Set cfg = ..Parse(configuration)
    If '$IsObject(cfg) Quit ""
    Quit cfg.%Get("modelName")_"|"_cfg.%Get("cachePath")_"|"_cfg.%Get("pythonPath")
}

/// `none`, `warming`, `ready` or `failed`. A registered pid that is no longer a live process is
/// `none`: the caller starts a new worker instead of waiting on a dead one.
ClassMethod State() As %String
{
    Set node = ..Registry()
    Set state = $G(@node@("state"))
    If (state = "") Quit "none"
    If (state = "failed") Quit "failed"
    Set pid = $G(@node@("pid"))
    If (pid = "") || ('$DATA(^$JOB(pid))) Quit "none"
    Quit state
}

/// The key of the model the registered worker holds or is loading.
ClassMethod LoadedKey() As %String
{
    Set node = ..Registry()
    Quit $G(@node@("key"))
}

/// Why the last load failed, as the load itself said it.
ClassMethod LastError() As %String
{
    Set node = ..Registry()
    Quit $G(@node@("error"))
}

/// Polls until the worker reaches `state`, for up to `seconds`. For the image's warm-up check, the
/// quickstart and the tests; the search path never waits on it.
ClassMethod WaitUntil(state As %String, seconds As %Numeric = 10) As %Boolean
{
    Set deadline = $ZH + seconds, reached = 0
    While ('reached) && ($ZH < deadline) {
        If (..State() = state) {
            Set reached = 1
        } Else {
            Hang 0.1
        }
    }
    Quit reached
}

/// Starts the worker for `configuration`, or for the `sentai-steps` row when none is given. Returns
/// at once: the load happens in the new process, which registers `warming` then `ready`.
/// 
/// Idempotent. A worker already warming or ready for the same model is left alone; a worker for
/// another model, a failed one, or a dead one is replaced. A lock decides who starts, so two
/// callers racing never start two workers. With no configuration and no row naming the in-process
/// provider there is nothing to start, which is not an error.
ClassMethod Start(configuration As %String = "") As %Status
{
    Set sc = $$$OK
    If (configuration = "") Set configuration = ..RowConfiguration()
    If (configuration = "") Quit sc
    Set node = ..Registry(), key = ..ModelKey(configuration)
    Lock +@node:2
    If '$TEST Quit sc
    Try {
        Set state = ..State()
        If ((state = "warming") || (state = "ready")) && (..LoadedKey() = key) {
            // Already there for this model.
        } Else {
            If (state = "warming") || (state = "ready") Do ..StopWorker()
            Kill @node
            Set @node@("state") = "warming", @node@("key") = key, @node@("startedAt") = $ZTIMESTAMP
            // The class to run is this class — the compiled one, never a name from input
            // (Constitution II) — so a subclass's hooks are the ones that load.
            Job ##class(sentai.search.EmbeddingWorker).Run($CLASSNAME(), configuration)::5
            If $TEST {
                Set @node@("pid") = $ZCHILD
            } Else {
                Set @node@("state") = "failed", @node@("error") = "the worker process could not be started"
            }
        }
    } Catch e {
        Set sc = e.AsStatus()
    }
    Lock -@node
    Quit sc
}

/// Stops the worker, if any, and clears the registration.
ClassMethod Stop() As %Status
{
    Set node = ..Registry()
    Lock +@node:2
    // Kept at once: every `If` below resets `$TEST`.
    Set locked = $TEST
    Do ..StopWorker()
    Kill @node
    If locked Lock -@node
    Quit $$$OK
}

/// Asks the worker to exit and waits for it. The caller holds the registration lock.
ClassMethod StopWorker()
{
    Set node = ..Registry(), event = ..Event(), pid = $G(@node@("pid"))
    Try {
        If $SYSTEM.Event.Defined(event) Do $SYSTEM.Event.Signal(event, $LISTBUILD(..#StopCaller, ""))
    } Catch e {
    }
    Set deadline = $ZH + ..#StopWait
    While (pid '= "") && $DATA(^$JOB(pid)) && ($ZH < deadline) {
        Hang 0.1
    }
    Try {
        If $SYSTEM.Event.Defined(event) Do $SYSTEM.Event.Delete(event)
    } Catch e {
    }
}

/// Asks the ready worker for the vector of `text`, waiting at most `timeout` seconds.
/// 
/// Returns the vector's display form, or "" with `reason` set: `warming` when there is no ready
/// worker to ask, `slow` when it did not answer in time, `error` when it answered a failure.
ClassMethod Ask(text As %String, timeout As %Numeric, Output reason As %String) As %String
{
    Set reason = "", vector = ""
    Set event = ..Event()
    If (..State() '= "ready") || ('$SYSTEM.Event.Defined(event)) {
        Set reason = "warming"
        Quit vector
    }
    Try {
        // A late reply to an earlier ask that timed out must not be read as this one's answer.
        Do $SYSTEM.Event.Clear($JOB)
        Do $SYSTEM.Event.Signal(event, $LISTBUILD($JOB, text))
        Set got = $SYSTEM.Event.WaitMsg("", timeout)
        If ($LIST(got, 1) '= 1) {
            Set reason = "slow"
        } Else {
            Set reply = $LIST(got, 2)
            If ($LIST(reply, 1) = 1) {
                Set vector = $LIST(reply, 2)
            } Else {
                Set reason = "error"
            }
        }
    } Catch e {
        Set reason = "error"
    }
    Quit vector
}

/// The job's entry point: runs `Serve` of the class that started it.
ClassMethod Run(workerClass As %String, configuration As %String)
{
    Do $CLASSMETHOD(workerClass, "Serve", configuration)
}

/// The worker's life: register, load, answer until told to stop, clean up.
ClassMethod Serve(configuration As %String)
{
    Set node = ..Registry(), event = ..Event()
    Set @node@("pid") = $JOB
    Set cfg = ..Parse(configuration)
    Set problem = ""
    Try {
        If '$IsObject(cfg) {
            Set problem = "the configuration is not a JSON object"
        } Else {
            Set problem = ..LoadModel(cfg.%Get("modelName"), cfg.%Get("cachePath"), cfg.%Get("pythonPath"))
        }
    } Catch e {
        Set problem = "load failed: "_e.DisplayString()
    }
    If (problem '= "") {
        Set @node@("state") = "failed", @node@("error") = problem
        Quit
    }
    If '$SYSTEM.Event.Defined(event) Do $SYSTEM.Event.Create(event)
    Set @node@("state") = "ready", @node@("readyAt") = $ZTIMESTAMP

    Set serving = 1
    While serving {
        Set got = $SYSTEM.Event.WaitMsg(event, 30)
        Set status = $LIST(got, 1)
        If (status = -1) {
            // The event was deleted: this worker has been stopped.
            Set serving = 0
        } ElseIf (status = 0) {
            // Idle. A worker that is no longer the registered one has been replaced.
            If ($G(@node@("pid")) '= $JOB) Set serving = 0
        } Else {
            Set msg = $LIST(got, 2), caller = $LIST(msg, 1)
            If (caller = ..#StopCaller) {
                Set serving = 0
            } Else {
                Do ..Answer(caller, $LIST(msg, 2))
            }
        }
    }
    If ($G(@node@("pid")) = $JOB) {
        Kill @node
        Try {
            If $SYSTEM.Event.Defined(event) Do $SYSTEM.Event.Delete(event)
        } Catch e {
        }
    }
}

/// Encodes one text and replies to the caller: `$LB(1, vector)` or `$LB(0, why)`. A caller that has
/// gone away is not an error for the worker.
ClassMethod Answer(caller As %Integer, text As %String)
{
    Try {
        Set reply = $LISTBUILD(1, ..Encode(text))
    } Catch e {
        Set reply = $LISTBUILD(0, e.DisplayString())
    }
    Try {
        Do $SYSTEM.Event.Signal(caller, reply)
    } Catch e {
    }
}

/// The `Configuration` of the `sentai-steps` row when that row names the in-process provider, else "".
ClassMethod RowConfiguration() As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EmbeddingClass, Configuration FROM %EMBEDDING.Config WHERE Name = ?", $PARAMETER($CLASSNAME(), "ConfigName"))
    If (rs.%SQLCODE < 0) || ('rs.%Next()) Quit ""
    If (rs.%Get("EmbeddingClass") '= $PARAMETER($CLASSNAME(), "ProviderClass")) Quit ""
    Quit rs.%Get("Configuration")
}

ClassMethod Parse(configuration As %String) As %DynamicObject
{
    Set cfg = ""
    Try {
        Set cfg = ##class(%DynamicObject).%FromJSON(configuration)
    } Catch e {
    }
    Quit cfg
}

/// "" when the packages import and the model is in the cache, else what is missing. Never
/// downloads: the model is placed at build time, or by the operator (research R-3, R-7).
ClassMethod CheckModel(config As %DynamicObject) As %String
{
    Quit ..CheckModelPy(config.%Get("modelName"), config.%Get("cachePath"), config.%Get("pythonPath"))
}

ClassMethod CheckModelPy(modelName As %String, cachePath As %String, pythonPath As %String) As %String [ Language = python ]
{
    import sys
    if pythonPath and pythonPath not in sys.path:
        sys.path.append(pythonPath)
    try:
        import sentence_transformers  # noqa: F401
        from huggingface_hub import try_to_load_from_cache
    except Exception as e:
        return "the Python package sentence-transformers cannot be imported: %s" % e
    found = try_to_load_from_cache(repo_id=modelName, filename="config.json", cache_dir=cachePath)
    if not isinstance(found, str):
        return "model %s is not in %s; download it there first" % (modelName, cachePath)
    return ""
}

/// Loads the model into this process, once. "" on success, else why it could not.
/// 
/// `trust_remote_code=False`: no code arrives with a model (Constitution II). `local_files_only`:
/// the cache is the only source, so a cut network costs nothing (research R-3: 146 s without it).
ClassMethod LoadModel(modelName As %String, cachePath As %String, pythonPath As %String) As %String [ Language = python ]
{
    import sys, types
    if pythonPath and pythonPath not in sys.path:
        sys.path.append(pythonPath)
    holder = sys.modules.get("_sentai_embed")
    if holder is None:
        holder = types.ModuleType("_sentai_embed")
        sys.modules["_sentai_embed"] = holder
    try:
        from sentence_transformers import SentenceTransformer
        holder.model = SentenceTransformer(modelName, cache_folder=cachePath or None, device="cpu",
                                           trust_remote_code=False, local_files_only=True)
    except Exception as e:
        return "load failed: %s" % e
    return ""
}

/// The vector of `text` from the loaded model, in the display form `%Library.Vector` converts.
ClassMethod Encode(text As %String) As %String [ Language = python ]
{
    import sys
    holder = sys.modules["_sentai_embed"]
    return str(holder.model.encode([text])[0].tolist())
}

}
