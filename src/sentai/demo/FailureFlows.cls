/// The two failure demos (docs/use-case-failure-demos.md): seeded flows that fail on
/// purpose, so a fresh `docker compose up -d --build` can show what the product does when
/// something goes wrong — the step's own `failureReason`, the join that stops everything
/// after a failed input, and a run that is never reported as success (Constitution IV).
///
/// The XData blocks are flow definitions, data not code (Constitution II): every step type
/// comes from the closed catalog (sentai.registry.StepType) and nothing an operator types
/// ever reaches this class. Each failure is the platform's real answer under parameters the
/// catalog itself declares:
///   - "failing-check" mirrors the weekly window with one change — a threshold no location
///     can ever satisfy (nothing is 100% free), so 01 always fails, 02 completes anyway, and
///     the ALL_MUST_SUCCEED join at 03 fails 03 and 04 without running them;
///   - "security-posture" asks for the posture report with failOnFindings, so any high
///     finding the platform reports (an enabled %All holder, auditing off) fails the step
///     with the platform's own text — and an operator without security administration sees
///     the platform's refusal as the reason instead, verbatim (Constitution III).
/// Seeding is idempotent by flow name, the same contract as sentai.demo.DemoFlows: a flow
/// of that name that already exists — the operator's own, edited or not — is returned
/// untouched, and a removed demo is not resurrected by a later `zpm load`.
Class sentai.demo.FailureFlows Extends %RegisteredObject
{

/// The demo keys — the only values `EnsureSeeded` accepts, so no runtime value can select
/// anything but a shipped definition (Constitution II).
Parameter FAILINGCHECK = "failing-check";

Parameter SECURITYPOSTURE = "security-posture";

/// The whole JSON object is indented inside the block: XData ends at a line starting with
/// `}` at column 0, and the payload is an object, so its own closing brace must not sit there.
XData FailingCheckWindow [ MimeType = application/json ]
{
  {
    "schemaVersion": 1,
    "name": "Maintenance window with a failing check",
    "defaultCategory": "Default",
    "steps": [
      {"id": "01", "type": "storage-headroom-check", "taskName": "Storage headroom", "namespace": "%SYS", "parameters": {"minFreePercent": 100}, "timeoutMinutes": 5, "wqmCategory": "Default"},
      {"id": "02", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "timeoutMinutes": 5, "wqmCategory": "Default"},
      {"id": "03", "type": "switch-journal", "taskName": "Switch journal", "namespace": "%SYS", "timeoutMinutes": 5, "wqmCategory": "Default"},
      {"id": "04", "type": "integrity-check", "taskName": "Integrity check - USER", "namespace": "USER", "timeoutMinutes": 10, "wqmCategory": "Default"}
    ],
    "edges": [
      {"source": "01", "target": "03"},
      {"source": "02", "target": "03"},
      {"source": "03", "target": "04"}
    ],
    "joins": [
      {"target": "03", "policy": "ALL_MUST_SUCCEED"}
    ],
    "canvasGeometry": {
      "viewport": {"x": 0, "y": 40, "zoom": 0.85},
      "nodes": {
        "01": {"x": 0, "y": 0, "width": 240},
        "02": {"x": 0, "y": 220, "width": 240},
        "03": {"x": 340, "y": 110, "width": 240},
        "04": {"x": 680, "y": 110, "width": 240}
      }
    }
  }
}

XData SecurityPostureFindings [ MimeType = application/json ]
{
  {
    "schemaVersion": 1,
    "name": "Security posture with fail-on-findings",
    "defaultCategory": "Default",
    "steps": [
      {"id": "01", "type": "security-posture-report", "taskName": "Security posture report", "namespace": "%SYS", "parameters": {"failOnFindings": true}, "timeoutMinutes": 5, "wqmCategory": "Default"}
    ],
    "edges": [],
    "joins": [],
    "canvasGeometry": {
      "viewport": {"x": 0, "y": 40, "zoom": 0.9},
      "nodes": {
        "01": {"x": 0, "y": 0, "width": 240}
      }
    }
  }
}

/// The demo's definition as a %DynamicObject — "" when `demo` is not one of the two shipped
/// keys. The sole reader of the XData blocks, the same reader pattern as
/// sentai.registry.StepType.GetCatalog().
ClassMethod Definition(demo As %String) As %DynamicObject
{
    Set block = ""
    If (demo = ..#FAILINGCHECK) { Set block = "FailingCheckWindow" }
    ElseIf (demo = ..#SECURITYPOSTURE) { Set block = "SecurityPostureFindings" }
    Quit:(block = "") ""
    Set stream = ##class(%Dictionary.CompiledXData).%OpenId(..%ClassName(1)_"||"_block).Data
    Quit ##class(%DynamicAbstractObject).%FromJSON(stream)
}

/// Idempotent seed: returns the id of the flow named `name` (the demo's own name when ""),
/// creating it (from the demo's payload, under `savedBy`) only when no flow of that name
/// exists. "" means the save failed or `demo` is not a shipped key — the caller decides what
/// to make of it. The image build calls this for both demos (iris-demo.script) so a fresh
/// stack already lists them; `zpm "install"` users seed by hand with the same two calls.
ClassMethod EnsureSeeded(demo As %String, name As %String = "", savedBy As %String = "sentai.demo") As %String
{
    Set def = ..Definition(demo)
    Quit:(def = "") ""
    If (name = "") Set name = def.name
    If ##class(sentai.model.Flow).NameIndexExists(name, .existingId) Quit existingId
    Do def.%Set("name", name)
    Set sc = ##class(sentai.model.Flow).SaveGraph(def, "", 0, savedBy, .id)
    If $$$ISERR(sc) Quit ""
    Quit id
}

/// Removes the flow named `name` (the API has no flow deletion); nothing happens when no
/// such flow exists. The children go first, the same explicit order sentai.demo.DemoFlows
/// uses (Cardinality = One refuses the other way, ERROR #5823). A flow the operator has
/// already dispatched is kept: its runs hold the history, so Remove refuses rather than
/// orphan it.
ClassMethod Remove(name As %String) As %Status
{
    If '##class(sentai.model.Flow).NameIndexExists(name, .flowId) Quit $$$OK
    Set runCount = 0
    &sql(SELECT COUNT(*) INTO :runCount FROM sentai_model.Run WHERE flow = :flowId)
    If +runCount Quit $$$ERROR($$$GeneralError, "SentaiFlowHasRuns: flow '"_name_"' has "_runCount_" run(s); their history is kept - clear the runs first if you really want the flow gone")
    &sql(DELETE FROM sentai_model.Step WHERE flow = :flowId)
    &sql(DELETE FROM sentai_model.Edge WHERE flow = :flowId)
    &sql(DELETE FROM sentai_model."Join" WHERE flow = :flowId)
    Quit ##class(sentai.model.Flow).%DeleteId(flowId)
}

}
