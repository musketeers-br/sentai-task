/// The link from a platform task back to the SentaiTask flow (and, for the legacy form, step)
/// that created it (spec 006 FR-005). The grammars are the product's own generators: the flow's
/// task (spec 015, `ScheduleService.TaskName`: "SentaiTask: "_flowId_" "_flowName) and the legacy
/// per-step task ("SentaiTask: "_flowId_"#"_stepId); any other name carries no origin. The name
/// is platform data, matched as data (no evaluation).
Class sentai.catalog.TaskOrigin Extends %RegisteredObject
{

Parameter GRAMMAR = "^SentaiTask: ([1-9][0-9]*)#([0-9A-Za-z_-]{1,8})$";

Parameter FLOWGRAMMAR = "^SentaiTask: ([1-9][0-9]*) (.+)$";

/// `stepId` is "" for a flow's task.
ClassMethod Parse(name As %String, Output flowId As %String, Output stepId As %String) As %Boolean
{
    Set (flowId, stepId) = ""
    Set matcher = ##class(%Regex.Matcher).%New(..#GRAMMAR, name)
    If matcher.Match() {
        Set flowId = matcher.Group(1), stepId = matcher.Group(2)
        Quit 1
    }
    Set matcher = ##class(%Regex.Matcher).%New(..#FLOWGRAMMAR, name)
    Quit:'matcher.Match() 0
    Set flowId = matcher.Group(1)
    Quit 1
}

/// {flowId, stepId (legacy form only), flowExists} for a generator name, or "" when the name does
/// not match. `flowExists` is read on every call (nothing is cached).
ClassMethod Resolve(name As %String) As %DynamicObject
{
    Quit:'..Parse(name, .flowId, .stepId) ""
    Set origin = {"flowId": (flowId)}
    Do:(stepId '= "") origin.%Set("stepId", stepId)
    Do origin.%Set("flowExists", ##class(sentai.model.Flow).%ExistsId(flowId), "boolean")
    Quit origin
}

/// Spec 015: a flow's task runs every step, so it is destructive when any step's type is;
/// `found` = 0 when a step's type is not in the catalog (then unknown, never a guess).
ClassMethod FlowIsDestructive(flowId As %String, Output found As %Boolean) As %Boolean
{
    Set found = 1, destructive = 0
    Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT type FROM sentai_model.Step WHERE flow = ?", flowId)
    While result.%Next() {
        Set type = result.%Get("type")
        If '##class(sentai.registry.StepType).IsKnownType(type) { Set found = 0 Quit }
        Set:##class(sentai.registry.StepType).IsDestructive(type) destructive = 1
    }
    Quit destructive
}

/// The type of step `stepId` of flow `flowId` (parameterized; the ids are data).
ClassMethod StepTypeOf(flowId As %String, stepId As %String, Output found As %Boolean) As %String
{
    Set found = 0
    Set statement = ##class(%SQL.Statement).%New()
    Quit:$$$ISERR(statement.%Prepare("SELECT type FROM sentai_model.Step WHERE flow = ? AND id = ?")) ""
    Set result = statement.%Execute(flowId, stepId)
    Quit:'result.%Next() ""
    Set found = 1
    Quit result.%Get("type")
}

}
