/// The "Weekly maintenance window" use case (docs/use-case-weekly-maintenance.md) as seeded
/// demo data. The XData block below IS the flow definition that document walks through —
/// data, not code (Constitution II): every step type it names comes from the closed catalog
/// (sentai.registry.StepType) and nothing an operator types ever reaches this class. Seeding
/// is idempotent by flow name: a flow of that name that already exists — the operator's own,
/// edited or not — is returned untouched, so the demo never clobbers anything, and a removed
/// demo is not resurrected by a later `zpm load`.
Class sentai.demo.DemoFlows Extends %RegisteredObject
{

/// The whole JSON object is indented inside the block: XData ends at a line starting with
/// `}` at column 0, and the payload is an object, so its own closing brace must not sit there.
XData WeeklyMaintenance [ MimeType = application/json ]
{
  {
    "schemaVersion": 1,
    "name": "Weekly maintenance window",
    "defaultCategory": "Default",
    "steps": [
      {"id": "01", "type": "storage-headroom-check", "taskName": "Storage headroom", "namespace": "%SYS", "parameters": {"minFreePercent": 15}, "timeoutMinutes": 10, "wqmCategory": "Default"},
      {"id": "02", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "timeoutMinutes": 10, "wqmCategory": "Default"},
      {"id": "03", "type": "switch-journal", "taskName": "Switch journal", "namespace": "%SYS", "timeoutMinutes": 5, "wqmCategory": "Default"},
      {"id": "04", "type": "integrity-check", "taskName": "Integrity check - USER", "namespace": "USER", "timeoutMinutes": 45, "wqmCategory": "Default"},
      {"id": "05", "type": "integrity-check", "taskName": "Integrity check - %SYS", "namespace": "%SYS", "timeoutMinutes": 45, "wqmCategory": "Default"},
      {"id": "06", "type": "purge-task-history", "taskName": "Purge task history", "namespace": "%SYS", "parameters": {"keepDays": 30}, "timeoutMinutes": 10, "wqmCategory": "Default"}
    ],
    "edges": [
      {"source": "01", "target": "03"},
      {"source": "02", "target": "03"},
      {"source": "03", "target": "04"},
      {"source": "03", "target": "05"},
      {"source": "04", "target": "06"},
      {"source": "05", "target": "06"}
    ],
    "joins": [
      {"target": "03", "policy": "ALL_MUST_SUCCEED"},
      {"target": "06", "policy": "ALL_MUST_SUCCEED"}
    ],
    "canvasGeometry": {
      "viewport": {"x": 0, "y": 40, "zoom": 0.85},
      "nodes": {
        "01": {"x": 0, "y": 0, "width": 240},
        "02": {"x": 0, "y": 220, "width": 240},
        "03": {"x": 340, "y": 110, "width": 240},
        "04": {"x": 680, "y": 0, "width": 240},
        "05": {"x": 680, "y": 220, "width": 240},
        "06": {"x": 1020, "y": 110, "width": 240}
      }
    }
  }
}

/// The flow definition as a %DynamicObject — the sole reader of the XData block, the same
/// reader pattern as sentai.registry.StepType.GetCatalog().
ClassMethod Payload() As %DynamicObject
{
    Set stream = ##class(%Dictionary.CompiledXData).%OpenId(..%ClassName(1)_"||WeeklyMaintenance").Data
    Quit ##class(%DynamicAbstractObject).%FromJSON(stream)
}

/// Idempotent seed: returns the id of the flow named `name`, creating it (from the XData
/// payload, under `savedBy`) only when no flow of that name exists. "" means the save
/// failed — the caller decides what to make of it. `zpm "install"` users seed by hand with
/// this one call; the compose image build calls it (iris-demo.script) so a fresh stack
/// already lists the example.
ClassMethod EnsureSeeded(name As %String = "Weekly maintenance window", savedBy As %String = "sentai.demo") As %String
{
    If ##class(sentai.model.Flow).NameIndexExists(name, .existingId) Quit existingId
    Set payload = ..Payload()
    Do payload.%Set("name", name)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, savedBy, .id)
    If $$$ISERR(sc) Quit ""
    Quit id
}

/// Removes the flow named `name` (the API has no flow deletion); nothing happens when no
/// such flow exists. A flow's children reference it with Cardinality = One, whose OnDelete
/// is noaction, so the platform refuses to delete a flow its steps still reference
/// (ERROR #5823) — the children go first, the same explicit order
/// SentaiTestCase.RemoveRunsAfter uses for runs. A flow the operator has already dispatched
/// is kept: its runs hold the history, so Remove refuses rather than orphan it.
ClassMethod Remove(name As %String = "Weekly maintenance window") As %Status
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
