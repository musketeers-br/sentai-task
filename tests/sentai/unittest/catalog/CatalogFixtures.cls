/// Platform-shaped fixtures for the task-catalog tests (spec 006 research R-1…R-5). Every body
/// is the management API's envelope `{status, console, result}`; scripted through
/// sentai.unittest.AdminApiDouble keyed by the full URL (GET) or base path (POST).
Class sentai.unittest.catalog.CatalogFixtures Extends %RegisteredObject
{

ClassMethod Envelope(result, errors As %DynamicArray = "") As %String
{
    Set status = {"errors": [], "summary": ""}
    If $IsObject(errors) Set status.errors = errors
    Set body = {"status": (status), "console": []}
    Do body.%Set("result", $S($IsObject(result):result, 1:{}))
    Quit body.%ToJSON()
}

/// A platform 404 body for a missing task (research R-1, verbatim shape).
ClassMethod NotFoundJSON(id As %String) As %String
{
    Set error = {"error": ("ERROR #5809: Object to Load not found, class '%SYS.Task', ID '"_id_"'"), "code": 5809, "domain": "%ObjectErrors", "id": "LoadObjectNotFound", "params": ["%SYS.Task", (id)]}
    Quit ..Envelope({}, [(error)])
}

ClassMethod ScriptList(entries As %DynamicArray, httpStatus As %Integer = 200)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", httpStatus, "", ..Envelope(entries))
}

ClassMethod ListEntry(id As %Integer, name As %String, namespace As %String = "%SYS", suspended As %Boolean = 0) As %DynamicObject
{
    Set e = {"Name": (name), "Type": "System", "Namespace": (namespace), "Description": "", "LastFinished": "", "NextScheduled": "2026-09-28 02:00:00"}
    Do e.%Set("Id", id, "number")
    Do e.%Set("Suspended", suspended, "boolean")
    Quit e
}

ClassMethod ScriptSingle(id As %Integer, taskClass As %String, runAsUser As %String = "_SYSTEM", timePeriod As %String = "Weekly", name As %String = "", namespace As %String = "%SYS")
{
    Set r = {"Name": (name), "RunAsUser": (runAsUser), "TaskClass": (taskClass), "NameSpace": (namespace), "TimePeriod": (timePeriod), "RunAfterGUID": ""}
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task?id="_id, "GET", 200, "", ..Envelope(r))
}

ClassMethod InfoResult(suspended As %Boolean = 0, status As %String = "1", error As %String = "", lastStarted As %String = "", lastFinished As %String = "", nextScheduled As %String = "2026-09-28 02:00:00") As %DynamicObject
{
    Set r = {"Type": "System", "LastSchedule": ""}
    Do r.%Set("Status", status)
    Do r.%Set("Error", error)
    Do r.%Set("LastStarted", lastStarted)
    Do r.%Set("LastFinished", lastFinished)
    Do r.%Set("NextScheduled", nextScheduled)
    Do r.%Set("Suspended", suspended, "boolean")
    Quit r
}

ClassMethod ScriptInfo(id As %Integer, result As %DynamicObject)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/info?id="_id, "GET", 200, "", ..Envelope(result))
}

/// Scripts list + single + info for one well-formed task.
ClassMethod ScriptTask(id As %Integer, name As %String, taskClass As %String, info As %DynamicObject = "", namespace As %String = "%SYS")
{
    Do ..ScriptSingle(id, taskClass, "_SYSTEM", "Weekly", name, namespace)
    Do ..ScriptInfo(id, $S($IsObject(info):info, 1:..InfoResult()))
}

/// A read value as TaskService hands it to TaskShape: {httpStatus, result, status}.
ClassMethod Read(httpStatus As %Integer, result = "", errors As %DynamicArray = "") As %DynamicObject
{
    Set status = {"errors": [], "summary": ""}
    If $IsObject(errors) Set status.errors = errors
    Set read = {"status": (status)}
    Do read.%Set("httpStatus", httpStatus, "number")
    If $IsObject(result) Do read.%Set("result", result)
    Quit read
}

}
