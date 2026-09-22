/// Work Queue Manager category read/write — immediate passthrough to the administrative
/// API (`/api/admin/v2/wqm-categories`), plus the nesting-invariant check and
/// `affectedTaskCount` (FR-033–FR-036). The platform is always the source of truth; the
/// local `sentai.model.Category` mirror is a read-optimization only (data-model.md).
Class sentai.wqm.CategoryService Extends %RegisteredObject
{

/// Lists every WQM category, mirroring the read locally as it goes.
ClassMethod List(bearerToken As %String) As %DynamicArray
{
    Set httpStatus = 0, location = ""
    Set body = ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/v2/wqm-categories", bearerToken, .httpStatus, .location)
    Set out = []
    Quit:'$IsObject(body) out

    Set iter = body."result".%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Set shaped = ..ShapeCategory(entry)
        Do out.%Push(shaped)
        Do ##class(sentai.model.Category).Mirror(shaped.name, shaped.defaultWorkers, shaped.maxActiveWorkers, shaped.maxWorkers, shaped.maxTotalWorkers, shaped.alwaysQueue)
    }
    Quit out
}

/// Reads one category plus affectedTaskCount (FR-035) — scheduled tasks outside the
/// current flow that use this category, computed against the local Step mirror.
ClassMethod Read(name As %String, excludeFlowId As %String, bearerToken As %String) As %DynamicObject
{
    Set list = ..List(bearerToken)
    Set iter = list.%GetIterator()
    While iter.%GetNext(.k, .entry) {
        If (entry.name = name) {
            Do entry.%Set("affectedTaskCount", ..AffectedTaskCount(name, excludeFlowId))
            Quit
        }
        Set entry = ""
    }
    Quit entry
}

/// Numeric fields the admin API may report as "Dynamic (N)" strings (evidence/09-wqm-categories.json)
/// are normalized to plain integers here — the dynamic ceiling's current value.
ClassMethod ShapeCategory(entry As %DynamicObject) As %DynamicObject
{
    Set out = {}
    Do out.%Set("name", entry."Name")
    Do out.%Set("defaultWorkers", ..NormalizeWorkerCount(entry."DefaultWorkers"))
    Do out.%Set("maxActiveWorkers", ..NormalizeWorkerCount(entry."MaxActiveWorkers"))
    Do out.%Set("maxWorkers", ..NormalizeWorkerCount(entry."MaxWorkers"))
    Do out.%Set("maxTotalWorkers", ..NormalizeWorkerCount(entry."MaxTotalWorkers"))
    Do out.%Set("alwaysQueue", entry."AlwaysQueue")
    Quit out
}

ClassMethod NormalizeWorkerCount(raw) As %Integer
{
    If $ISVALIDNUM(raw) Quit +raw
    Set text = $G(raw)
    If (text [ "(") {
        Quit +$PIECE($PIECE(text, "(", 2), ")", 1)
    }
    Quit +text
}

/// Count of scheduled tasks, outside `excludeFlowId`, whose wqmCategory equals `name`
/// (FR-035). Uses the local Step mirror — the product's own composition data — which is
/// the only place "scheduled tasks of this product" is knowable without a platform-wide
/// scan.
ClassMethod AffectedTaskCount(name As %String, excludeFlowId As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(DISTINCT flow) AS c FROM sentai.model.Step WHERE wqmCategory = ? AND flow <> ?")
    Set result = rs.%Execute(name, $S(excludeFlowId '= "":excludeFlowId, 1:"-1"))
    Do result.%Next()
    Quit result.%Get("c")
}

/// Writes a category: blocks (returns $$$ERROR) on an invariant violation (FR-034,
/// error not warning) before ever calling the administrative API; on success, the write
/// is an immediate passthrough and the local mirror is refreshed. Never retroactively
/// affects a run already in progress (FR-036) — this method touches no Run/StepRun.
ClassMethod Write(payload As %DynamicObject, bearerToken As %String) As %Status
{
    If '##class(sentai.model.Category).SatisfiesInvariant(payload.defaultWorkers, payload.maxActiveWorkers, payload.maxWorkers, payload.maxTotalWorkers) {
        Quit $$$ERROR($$$GeneralError, "SentaiInvariantViolated: defaultWorkers<=maxActiveWorkers<=maxWorkers<=maxTotalWorkers must hold")
    }

    Set body = {}
    Do body.%Set("Name", payload.name)
    Do body.%Set("DefaultWorkers", payload.defaultWorkers)
    Do body.%Set("MaxActiveWorkers", payload.maxActiveWorkers)
    Do body.%Set("MaxWorkers", payload.maxWorkers)
    Do body.%Set("MaxTotalWorkers", payload.maxTotalWorkers)
    Do body.%Set("AlwaysQueue", payload.alwaysQueue)

    Set httpStatus = 0, location = ""
    Do ##class(sentai.dispatch.AdminApiClient).Post("/api/admin/v2/wqm-categories/"_payload.name, bearerToken, body, .httpStatus, .location)
    If (httpStatus >= 300) Quit $$$ERROR($$$GeneralError, "SentaiAdminApiError: wqm-categories write returned HTTP "_httpStatus)

    Quit ##class(sentai.model.Category).Mirror(payload.name, payload.defaultWorkers, payload.maxActiveWorkers, payload.maxWorkers, payload.maxTotalWorkers, payload.alwaysQueue)
}

}
