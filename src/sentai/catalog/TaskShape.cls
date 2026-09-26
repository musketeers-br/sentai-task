/// Pure mapping from the platform's per-task reads to the catalog task (spec 006 data-model.md).
/// Every value is the platform's own; a read that failed leaves its fields absent and adds an
/// `unavailable` entry carrying the platform's status verbatim (FR-009). Nothing is defaulted.
/// A read is a value `{httpStatus, result, status}` built by TaskService.PlatformRead.
Class sentai.catalog.TaskShape Extends %RegisteredObject
{

/// `listEntry` is the list read's row (source of name/namespace in the list); "" for the item
/// read, where they come from the single read (`Name`, `NameSpace`).
ClassMethod Build(taskId As %Integer, listEntry As %DynamicObject, singleRead As %DynamicObject, infoRead As %DynamicObject) As %DynamicObject
{
    Set task = {}
    Set unavailable = []
    Do task.%Set("taskId", +taskId, "number")

    Set singleOk = ..IsOk(singleRead)
    If $IsObject(listEntry) {
        Do ..Copy(listEntry, "Name", task, "name")
        Do ..Copy(listEntry, "Namespace", task, "namespace")
    } ElseIf singleOk {
        Do ..Copy(singleRead.result, "Name", task, "name")
        Do ..Copy(singleRead.result, "NameSpace", task, "namespace")
    }

    If task.%IsDefined("name") {
        Set origin = ##class(sentai.catalog.TaskOrigin).Resolve(task.name)
        If $IsObject(origin) Do task.%Set("origin", origin)
    }

    If singleOk {
        Do ..Copy(singleRead.result, "TaskClass", task, "class")
        Do ..Copy(singleRead.result, "RunAsUser", task, "runAsUser")
        Do ..Copy(singleRead.result, "TimePeriod", task, "timePeriod")
    } Else {
        Do unavailable.%Push(..Unavailable("single", ["class", "runAsUser", "timePeriod"], singleRead))
    }

    If ..IsOk(infoRead) {
        Set info = infoRead.result
        Do ..Copy(info, "NextScheduled", task, "nextRun")
        Do ..Copy(info, "LastStarted", task, "lastStarted")
        Do ..Copy(info, "LastFinished", task, "lastFinished")
        If info.%IsDefined("Status") Do task.%Set("status", ..StatusText(info.%Get("Status")))
        Do ..Copy(info, "Error", task, "lastError")
        If info.%IsDefined("Suspended") Do task.%Set("suspended", ''info.%Get("Suspended"), "boolean")
        // Deprecated alias (FR-010), carrying the corrected value.
        If task.%IsDefined("lastFinished") Do task.%Set("lastRun", task.lastFinished)
    } Else {
        Do unavailable.%Push(..Unavailable("info", ["nextRun", "lastStarted", "lastFinished", "status", "lastError", "suspended"], infoRead))
    }

    Do ..ApplyDestructiveness(task)

    If unavailable.%Size() Do task.%Set("unavailable", unavailable)
    Quit task
}

/// Recent runs for the item read (research R-4): up to 5 rows of the platform's descending history
/// whose `Routine` equals the task's class (administrative events carry `TASKMGR`), with the
/// platform's own keys and values and no computed duration (its precision is minutes). Without
/// the class, executions cannot be told from events, so the field is absent and flagged with the
/// single read; a failed history read is flagged with its own status. Never an empty list
/// pretending there were no runs.
ClassMethod AttachRecentRuns(task As %DynamicObject, historyRead As %DynamicObject, singleRead As %DynamicObject)
{
    If 'task.%IsDefined("class") {
        Do ..AddUnavailable(task, ..Unavailable("history", ["recentRuns"], singleRead))
        Quit
    }
    If '..IsOk(historyRead) || (historyRead.result.%ClassName(1) '= "%Library.DynamicArray") {
        Do ..AddUnavailable(task, ..Unavailable("history", ["recentRuns"], historyRead))
        Quit
    }
    Set runs = [], iter = historyRead.result.%GetIterator()
    While iter.%GetNext(.k, .row) && (runs.%Size() < 5) {
        Continue:'$IsObject(row)
        Continue:(row.%Get("Routine") '= task.class)
        Set run = {}
        For key = "LastStart", "Completed", "Status", "Result", "Username", "LogDatetime" {
            Do ..Copy(row, key, run, key)
        }
        Do runs.%Push(run)
    }
    Do task.%Set("recentRuns", runs)
}

ClassMethod AddUnavailable(task As %DynamicObject, entry As %DynamicObject)
{
    If 'task.%IsDefined("unavailable") Do task.%Set("unavailable", [])
    Do task.unavailable.%Push(entry)
}

/// The platform's `Status` (research R-5): "1" and any value that is not a serialized error pass
/// through; a serialized %Status becomes the platform's own text for it, which equals the
/// history's `Status` and the portal's `DisplayStatus`.
ClassMethod StatusText(status As %String) As %String
{
    If ($EXTRACT(status, 1, 2) '= "0 ") Quit status
    Set text = status
    Try {
        If $SYSTEM.Status.IsError(status) Set text = $SYSTEM.Status.GetErrorText(status)
    } Catch {
        Set text = status
    }
    Quit text
}

/// The platform's error texts from its `status` object, joined; "" when it gave none.
ClassMethod ErrorText(platformStatus As %DynamicObject) As %String
{
    Quit:'$IsObject(platformStatus) ""
    Quit:'$IsObject(platformStatus.errors) ""
    Set text = "", iter = platformStatus.errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Set one = $S($IsObject(e):e.error, 1:e)
        Set text = text_$S(text = "":"", 1:"; ")_one
    }
    Quit text
}

/// Destructiveness from the step-type catalog only (data-model §Destructiveness): rule 1, the
/// class is unavailable → unknown; rule 2, a catalog entry names the class → its `destructive`;
/// rule 3, the product's own scheduled task whose flow and step exist → the step type's
/// `destructive`; rule 4, anything else → unknown. Never a guess.
ClassMethod ApplyDestructiveness(task As %DynamicObject)
{
    If 'task.%IsDefined("class") Do ..SetDestructive(task, 0, 1) Quit
    Set destructive = ##class(sentai.registry.StepType).DestructiveByClass(task.class, .known)
    If known Do ..SetDestructive(task, destructive, 0) Quit
    If (task.class = "sentai.dispatch.ScheduledFlowTask") && task.%IsDefined("origin") && task.origin.flowExists {
        Set type = ##class(sentai.catalog.TaskOrigin).StepTypeOf(task.origin.flowId, task.origin.stepId, .found)
        If found && ##class(sentai.registry.StepType).IsKnownType(type) {
            Do ..SetDestructive(task, ##class(sentai.registry.StepType).IsDestructive(type), 0)
            Quit
        }
    }
    Do ..SetDestructive(task, 0, 1)
}

ClassMethod SetDestructive(task As %DynamicObject, destructive As %Boolean, unknown As %Boolean)
{
    Do task.%Set("destructive", ''destructive, "boolean")
    Do task.%Set("destructiveUnknown", ''unknown, "boolean")
    // Deprecated alias (FR-010).
    Do task.%Set("isDestructive", ''destructive, "boolean")
}

ClassMethod IsOk(read As %DynamicObject) As %Boolean
{
    Quit $IsObject(read) && (read.httpStatus = 200) && $IsObject(read.result)
}

ClassMethod Unavailable(read As %String, fields As %DynamicArray, value As %DynamicObject) As %DynamicObject
{
    Set u = {"read": (read), "fields": (fields)}
    Do u.%Set("httpStatus", $S($IsObject(value):+value.httpStatus, 1:0), "number")
    If $IsObject(value) && $IsObject(value.status) Do u.%Set("platformStatus", value.status)
    Quit u
}

/// Copies a key only when the platform sent it (absent stays absent).
ClassMethod Copy(from As %DynamicObject, key As %String, to As %DynamicObject, as As %String)
{
    If from.%IsDefined(key) Do to.%Set(as, from.%Get(key))
}

}
