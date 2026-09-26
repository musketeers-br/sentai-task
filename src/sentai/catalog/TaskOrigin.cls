/// The link from a platform task back to the SentaiTask flow and step that created it (spec 006
/// FR-005). The grammar is the product's own generator (`Dispatcher.CreateNativeTask`:
/// "SentaiTask: "_flowId_"#"_stepId) with the flow %ID and the flow schema's stepId pattern;
/// any other name carries no origin. The name is platform data, matched as data (no evaluation).
Class sentai.catalog.TaskOrigin Extends %RegisteredObject
{

Parameter GRAMMAR = "^SentaiTask: ([1-9][0-9]*)#([0-9A-Za-z_-]{1,8})$";

ClassMethod Parse(name As %String, Output flowId As %String, Output stepId As %String) As %Boolean
{
    Set (flowId, stepId) = ""
    Set matcher = ##class(%Regex.Matcher).%New(..#GRAMMAR, name)
    Quit:'matcher.Match() 0
    Set flowId = matcher.Group(1), stepId = matcher.Group(2)
    Quit 1
}

/// {flowId, stepId, flowExists} for a generator name, or "" when the name does not match.
/// `flowExists` is read on every call (nothing is cached).
ClassMethod Resolve(name As %String) As %DynamicObject
{
    Quit:'..Parse(name, .flowId, .stepId) ""
    Set origin = {"flowId": (flowId), "stepId": (stepId)}
    Do origin.%Set("flowExists", ##class(sentai.model.Flow).%ExistsId(flowId), "boolean")
    Quit origin
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
