/// Read access to the catalog of tasks already scheduled on the instance — including
/// tasks not created by this product (FR-038, FR-039). P3, reducible: the first
/// candidate to cut if delivery time does not allow it (spec.md).
Class sentai.catalog.TaskService Extends %RegisteredObject
{

/// GET /api/admin/v2/tasks, filtered client-side by free text, namespace, scheduling
/// state, and destructive flag (FR-038). `isDestructive` for a task is inferred from its
/// mapped step type when its class matches the closed registry; otherwise reported false
/// (a platform-native task this product does not know about is never assumed destructive).
ClassMethod List(bearerToken As %String, q As %String = "", namespace As %String = "", filter As %String = "all", destructiveOnly As %Boolean = 0) As %DynamicObject
{
    Set httpStatus = 0, location = ""
    Set body = ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/v2/tasks", bearerToken, .httpStatus, .location)

    Set items = []
    Set total = 0, matched = 0

    If $IsObject(body) && $IsObject(body."result") {
        Set iter = body."result".%GetIterator()
        While iter.%GetNext(.k, .entry) {
            Set total = total + 1
            Set shaped = ..ShapeTask(entry)

            If (q '= "") && ('(shaped.name [ q)) Continue
            If (namespace '= "") && (shaped.namespace '= namespace) Continue
            If (filter = "scheduled") && shaped.suspended Continue
            If (filter = "suspended") && 'shaped.suspended Continue
            If destructiveOnly && 'shaped.isDestructive Continue

            Set matched = matched + 1
            Do items.%Push(shaped)
        }
    }

    Set out = {}
    Do out.%Set("total", total)
    Do out.%Set("matched", matched)
    Do out.%Set("items", items)
    Quit out
}

ClassMethod ShapeTask(entry As %DynamicObject) As %DynamicObject
{
    Set out = {}
    Do out.%Set("taskId", entry."Id")
    Do out.%Set("name", entry."Name")
    Do out.%Set("className", $G(entry."Type"))
    Do out.%Set("namespace", entry."Namespace")
    Do out.%Set("nextRun", entry."NextScheduled")
    Do out.%Set("lastRun", entry."LastFinished")
    Do out.%Set("state", $S(entry."Suspended":"cancelled", 1:"queued"))
    Do out.%Set("runAsUser", "")
    Do out.%Set("isDestructive", 0)
    Do out.%Set("suspended", entry."Suspended")
    Quit out
}

/// Suspends or resumes a scheduled task (FR-039); the new state is reflected on the next
/// read of that task.
ClassMethod Suspend(taskId As %Integer, suspended As %Boolean, bearerToken As %String) As %Status
{
    Set body = {}
    Do body.%Set("suspended", suspended)
    Set httpStatus = 0, location = ""
    Do ##class(sentai.dispatch.AdminApiClient).Post("/api/admin/v2/tasks/"_taskId_"/suspend", bearerToken, body, .httpStatus, .location)
    If (httpStatus >= 300) Quit $$$ERROR($$$GeneralError, "SentaiAdminApiError: task suspend returned HTTP "_httpStatus)
    Quit $$$OK
}

}
