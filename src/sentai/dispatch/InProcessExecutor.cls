/// Runs a declared in-process step on a %SYSTEM.WorkMgr worker (spec 005). The worker takes the
/// identity of the process that queued it — the run loop, i.e. the dispatching operator
/// (research.md R-1) — so the platform decides, at use time, whether that operator may do the
/// work (Constitution III).
/// 
/// The class that runs is read from the catalog by the step's `type` only; properties are set by
/// iterating the declared schema, never the keys of the step's JSON (Constitution II). This class
/// never reads Step.customClass.
Class sentai.dispatch.InProcessExecutor Extends %RegisteredObject
{

/// StepRun.result holds at most this many characters (data-model.md §Result size).
Parameter MAXRESULT = 8000;

/// Worker entry, queued by WaveDispatcher.StartStep with the StepRun already `running`. Builds
/// the task from the catalog, runs it in RunTask's frame, then — back in this frame and
/// namespace — records the runner, the result and the terminal state through the locked
/// transition (retried on a lock timeout; a loser to a timeout or cancel records nothing).
ClassMethod Run(stepRunGuid As %String) As %Status
{
    Set stepRun = ##class(sentai.model.StepRun).GuidIndexOpen(stepRunGuid, 0, .sc)
    If '$IsObject(stepRun) Quit $S($$$ISERR(sc):sc, 1:$$$ERROR($$$GeneralError, "SentaiNotFound: step run "_stepRunGuid))
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(stepRun.run.flowGetObjectId(), stepRun.stepId, 0, .sc)
    If '$IsObject(step) Quit $S($$$ISERR(sc):sc, 1:$$$ERROR($$$GeneralError, "SentaiNotFound: step "_stepRun.stepId))

    Kill outcome
    Set sc = ..NewTask(step.type, step.parameters, .task)
    If $$$ISERR(sc) {
        Set outcome("ok") = 0, outcome("reason") = $SYSTEM.Status.GetErrorText(sc)
        // Nothing ran: no runner is recorded.
        Set outcome("result") = "", outcome("user") = ""
    } Else {
        Do ..RunTask(task, .outcome)
    }

    Set newState = $S(outcome("ok"):"completed", 1:"failed")
    Set result = ..FitResult(outcome("result"))
    For attempt = 1:1:3 {
        Set sc = ##class(sentai.model.StepRun).TransitionLocked(stepRunGuid, newState, outcome("reason"), result, outcome("user"))
        Quit:$$$ISOK(sc)
        Quit:($SYSTEM.Status.GetErrorText(sc) [ "SentaiIllegalTransition")
    }
    Quit sc
}

/// A new task object of the catalog's class for `type` with its declared parameters set.
/// Refuses a type that is not in-process or whose class is not installed.
ClassMethod NewTask(type As %String, parameters As %DynamicObject, Output task As %SYS.Task.Definition) As %Status
{
    Set task = ""
    Set class = ##class(sentai.registry.StepType).GetTargetClass(type)
    If (##class(sentai.registry.StepType).GetExecutor(type) '= "in-process") || '##class(sentai.registry.StepType).ClassIsInstalled(class) {
        Quit $$$ERROR($$$GeneralError, "Step type '"_type_"' has no installed in-process class")
    }
    Set task = $CLASSMETHOD(class, "%New")
    Quit ..ApplyParameters(task, ##class(sentai.registry.StepType).GetParameterSchema(type), parameters)
}

/// Sets each property the schema declares from the step's value, or the declared default when
/// the key is absent. Keys the schema does not declare are never read.
ClassMethod ApplyParameters(task As %SYS.Task.Definition, schema As %DynamicArray, parameters As %DynamicObject) As %Status
{
    Set hasParameters = $IsObject(parameters)
    Set iter = schema.%GetIterator()
    While iter.%GetNext(.k, .def) {
        If hasParameters && parameters.%IsDefined(def.name) {
            Set value = parameters.%Get(def.name)
        } ElseIf def.%IsDefined("default") {
            Set value = def.default
        } Else {
            Continue
        }
        Set $PROPERTY(task, def.property) = value
    }
    Quit $$$OK
}

/// Runs `task` in its own frame. `New $NAMESPACE` undoes a namespace switch made by the task
/// (native tasks move to %SYS and stay there, research.md R-5). Returns plain values only:
///   outcome("ok")     1 / 0
///   outcome("reason") the error text verbatim ($SYSTEM.Status.GetErrorText or DisplayString)
///   outcome("result") the task's Result property when it has one, else ""
///   outcome("user")   $USERNAME the task ran as
ClassMethod RunTask(task As %SYS.Task.Definition, ByRef outcome) As %Status
{
    New $NAMESPACE
    Set home = $NAMESPACE
    Kill outcome
    Set outcome("user") = $USERNAME, outcome("result") = ""
    Try {
        Set sc = task.OnTask()
        Set outcome("ok") = $$$ISOK(sc)
        Set outcome("reason") = $S($$$ISOK(sc):"", 1:$SYSTEM.Status.GetErrorText(sc))
    }
    Catch ex {
        Set outcome("ok") = 0
        Set outcome("reason") = ex.DisplayString()
    }
    // Read the result from our own namespace, where the task's class is visible.
    Set:($NAMESPACE '= home) $NAMESPACE = home
    Try {
        Set outcome("result") = $PROPERTY(task, "Result")
    }
    Catch {
        Set outcome("result") = ""
    }
    Quit $$$OK
}

/// Makes a result fit StepRun.result as valid JSON (data-model.md §Result size): elements are
/// dropped from the end of the largest top-level array, adding "truncated": true and
/// "omitted": n; when that cannot fit, {"truncated": true, "originalLength": n}.
ClassMethod FitResult(json As %String) As %String
{
    Quit:(json = "") ""
    Set length = $L(json)
    Try {
        Set obj = ##class(%DynamicAbstractObject).%FromJSON(json)
    }
    Catch {
        Set obj = ""
    }
    If '$IsObject(obj) Quit {"truncated": true, "originalLength": (length)}.%ToJSON()
    Quit:(length <= ..#MAXRESULT) json

    // The largest top-level array, by serialized size.
    Set largest = "", largestSize = 0
    If obj.%IsA("%DynamicObject") {
        Set iter = obj.%GetIterator()
        While iter.%GetNext(.key, .value) {
            Continue:(obj.%GetTypeOf(key) '= "array")
            Set size = $L(value.%ToJSON())
            If (size > largestSize) Set largest = key, largestSize = size
        }
    }
    If (largest '= "") {
        Set all = obj.%Get(largest), total = all.%Size()
        // Binary search for the most elements that still fit.
        Set low = 0, high = total - 1, best = ""
        While (low <= high) {
            Set keep = (low + high) \ 2
            Set candidate = ..KeepFirst(obj, largest, all, keep)
            If ($L(candidate) <= ..#MAXRESULT) {
                Set best = candidate, low = keep + 1
            } Else {
                Set high = keep - 1
            }
        }
        Quit:(best '= "") best
    }
    Quit {"truncated": true, "originalLength": (length)}.%ToJSON()
}

/// `obj` serialized with array `key` cut to its first `keep` elements, plus the markers.
ClassMethod KeepFirst(obj As %DynamicObject, key As %String, all As %DynamicArray, keep As %Integer) As %String
{
    Set copy = ##class(%DynamicObject).%FromJSON(obj.%ToJSON())
    Set part = []
    For i = 0:1:(keep - 1) {
        Do part.%Push(all.%Get(i))
    }
    Do copy.%Set(key, part)
    Do copy.%Set("truncated", 1, "boolean")
    Do copy.%Set("omitted", all.%Size() - keep)
    Quit copy.%ToJSON()
}

}
