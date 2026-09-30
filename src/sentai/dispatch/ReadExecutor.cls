/// Spec 013: runs a `platform-read` step (a report) on a WorkMgr worker, like an in-process step
/// (spec 005): the step is already `running`; the worker reads the management API of the instance
/// the step runs on with the run's credential for it, builds the report with the class the
/// registry declares for the type, and ends the step through the locked transition (a loser to a
/// cancel or timeout records nothing).
Class sentai.dispatch.ReadExecutor Extends %RegisteredObject
{

/// Report keys never cut when the result must shrink (plan D-3).
Parameter PROTECTED = "summary,findings";

ClassMethod Run(stepRunGuid As %String) As %Status
{
    Set stepRun = ##class(sentai.model.StepRun).GuidIndexOpen(stepRunGuid, 0, .sc)
    If '$IsObject(stepRun) Quit $S($$$ISERR(sc):sc, 1:$$$ERROR($$$GeneralError, "SentaiNotFound: step run "_stepRunGuid))
    Set run = stepRun.run
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(run.flowGetObjectId(), stepRun.stepId, 0, .sc)
    If '$IsObject(step) Quit $S($$$ISERR(sc):sc, 1:$$$ERROR($$$GeneralError, "SentaiNotFound: step "_stepRun.stepId))

    // The instance and the credential: the target's, frozen at dispatch, or the run's own.
    Set base = stepRun.targetBaseUrl
    If (base '= "") {
        Set token = ##class(sentai.dispatch.WaveDispatcher).TargetToken(run.guid, stepRun.executedOn)
        Set who = ##class(sentai.dispatch.WaveDispatcher).TargetSub(run.guid, stepRun.executedOn)
    } Else {
        Set token = ##class(sentai.dispatch.WaveDispatcher).RunToken(run.guid)
        Set who = run.dispatchedBy
    }

    Set report = "", reason = ""
    Set sc = ..Build(step.type, step.parameters, ##class(sentai.steps.reports.Reader).For(base, token), .report)
    If $$$ISERR(sc) Set reason = $SYSTEM.Status.GetErrorText(sc)
    If $IsObject(report) Do report.%Set("instance", $S(base '= "":stepRun.executedOn, 1:"local"))
    Set result = $S($IsObject(report):..FitResult(report.%ToJSON(), ..#PROTECTED), 1:"")

    Set newState = $S($$$ISOK(sc):"completed", 1:"failed")
    For attempt = 1:1:3 {
        Set tsc = ##class(sentai.model.StepRun).TransitionLocked(stepRunGuid, newState, reason, result, who)
        Quit:$$$ISOK(tsc)
        Quit:($SYSTEM.Status.GetErrorText(tsc) [ "SentaiIllegalTransition")
    }
    Quit tsc
}

/// The declared class for `type` builds the report; refuses a type that is not `platform-read`.
ClassMethod Build(type As %String, parameters As %DynamicObject, reader As sentai.steps.reports.Reader, Output report As %DynamicObject) As %Status
{
    Set report = ""
    Set class = ##class(sentai.registry.StepType).GetTargetClass(type)
    If (##class(sentai.registry.StepType).GetExecutor(type) '= "platform-read") || '##class(sentai.registry.StepType).IsInstalled(type) {
        Quit $$$ERROR($$$GeneralError, "Step type '"_type_"' has no installed report class")
    }
    Try {
        Set sc = $CLASSMETHOD(class, "Build", reader, ..Parameters(type, parameters), .report)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The declared parameters with their defaults applied; keys the schema does not declare are never
/// read (the rule of InProcessExecutor.ApplyParameters).
ClassMethod Parameters(type As %String, parameters As %DynamicObject) As %DynamicObject
{
    Set out = {}, has = $IsObject(parameters)
    Set it = ##class(sentai.registry.StepType).GetParameterSchema(type).%GetIterator()
    While it.%GetNext(.k, .def) {
        If has && parameters.%IsDefined(def.name) {
            Set value = parameters.%Get(def.name), json = parameters.%GetTypeOf(def.name)
        } ElseIf def.%IsDefined("default") {
            Set value = def.default, json = def.%GetTypeOf("default")
        } Else {
            Continue
        }
        If (json = "boolean") { Do out.%Set(def.name, value, "boolean") } Else { Do out.%Set(def.name, value) }
    }
    Quit out
}

/// Fits the report into StepRun.result (8,000 characters) without ever cutting the `protected`
/// keys: the largest details arrays are cut first, keeping valid JSON with "truncated" and
/// "omitted" markers; if the protected keys alone are too big, findings are cut from the end
/// (info last) and summary.findingsOmitted says how many.
ClassMethod FitResult(json As %String, protected As %String) As %String
{
    Set max = ##class(sentai.dispatch.InProcessExecutor).#MAXRESULT
    Quit:($L(json) <= max) json
    Set obj = ##class(%DynamicAbstractObject).%FromJSON(json)
    Set details = obj.details, omitted = 0
    // The markers are counted while cutting: added afterwards, they could push the report back
    // over the limit and cost a finding (spec 020 finding).
    Do obj.%Set("truncated", 1, "boolean")
    Do obj.%Set("omitted", 0)
    // Cut the largest array inside details until it fits, one element at a time from the end.
    For {
        Quit:($L(obj.%ToJSON()) <= max)
        Set largest = "", size = 0
        If $IsObject(details) {
            Set it = details.%GetIterator()
            While it.%GetNext(.key, .value) {
                Continue:(details.%GetTypeOf(key) '= "array")
                Set s = $L(value.%ToJSON())
                If (s > size) && (value.%Size() > 0) Set largest = key, size = s
            }
        }
        Quit:(largest = "")
        Do details.%Get(largest).%Remove(details.%Get(largest).%Size() - 1)
        Set omitted = omitted + 1
        Do obj.%Set("omitted", omitted)
    }
    If (omitted = 0) {
        Do obj.%Remove("truncated")
        Do obj.%Remove("omitted")
    }
    // Still too big: the findings themselves, least severe last.
    Set cut = 0
    While ($L(obj.%ToJSON()) > max) && $IsObject(obj.findings) && (obj.findings.%Size() > 0) {
        Do obj.findings.%Remove(obj.findings.%Size() - 1)
        Set cut = cut + 1
    }
    Do:(cut > 0) obj.summary.%Set("findingsOmitted", cut)
    Quit obj.%ToJSON()
}

}
