/// Compiles a validated flow into native tasks through the platform's management API (FR-031):
/// one `POST /api/admin/v2/task` per step, with the operator's own token. The platform decides
/// who may create tasks (%Admin_Task or %Admin_Operate) and its refusal is the answer, verbatim
/// (Constitution III). Creating %SYS.Task in-process skipped that privilege (spec 006 research
/// R-1), which is why this path replaced it. Results are outcome values `{httpStatus, body}` or
/// `{httpStatus, problem}` (Constitution IV), written by sentai.rest.Dispatcher.
Class sentai.dispatch.NativeScheduler Extends %RegisteredObject
{

/// Every step's task, in step order. A refusal stops at that step and deletes the tasks this
/// request already created, with the same token, so a flow is never left half-scheduled.
ClassMethod Schedule(flowId As %String, bearerToken As %String) As %DynamicObject
{
    Set taskIds = []
    Set steps = ..StepsOf(flowId, .problem)
    If $IsObject(problem) Quit problem
    For i = 1:1:$LISTLENGTH(steps) {
        Set stepId = $LIST(steps, i)
        Set call = ##class(sentai.catalog.TaskService).PlatformPost("/api/admin/v2/task", ..TaskBody(flowId, stepId), bearerToken)
        If (call.httpStatus < 200) || (call.httpStatus >= 300) {
            Do ..RollBack(taskIds, bearerToken)
            Return ##class(sentai.catalog.TaskService).Refusal(call)
        }
        // The create answers without the task's id: the platform's own list gives it.
        Set name = ..TaskName(flowId, stepId)
        Set list = ##class(sentai.catalog.TaskService).PlatformRead("/api/admin/v2/tasks", bearerToken)
        If (list.httpStatus '= 200) || '$IsObject(list.result) {
            Do ..RollBack(taskIds, bearerToken)
            Return ##class(sentai.catalog.TaskService).Refusal(list)
        }
        Set taskId = ..NewestIdNamed(list.result, name)
        If (taskId = "") {
            Do ..RollBack(taskIds, bearerToken)
            Return ##class(sentai.catalog.TaskService).Problem(502, "SCHEDULE_NOT_CONFIRMED: the platform accepted the create but lists no task named '"_name_"'")
        }
        Do taskIds.%Push(taskId)
    }
    Quit ##class(sentai.catalog.TaskService).Ok({"taskIds": (taskIds)})
}

/// The flow's step ids in order, read with the operator's own SQL privileges. A refused or failed
/// read sets `problem` (an outcome value) instead of passing for a flow with no steps.
ClassMethod StepsOf(flowId As %String, Output problem) As %List
{
    Set problem = "", steps = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT id FROM sentai_model.Step WHERE flow = ? ORDER BY id", flowId)
    If (rs.%SQLCODE < 0) {
        Set problem = ..SqlProblem(rs.%SQLCODE, rs.%Message)
        Quit ""
    }
    While rs.%Next(.sc) {
        Set steps = steps_$LB(rs.%Get("id"))
    }
    If (rs.%SQLCODE < 0) Set problem = ..SqlProblem(rs.%SQLCODE, rs.%Message)
    Quit steps
}

/// A platform SQL refusal, verbatim: -99 (privilege violation) is the platform refusing this
/// operator → 403; any other error is a failure → 500.
ClassMethod SqlProblem(sqlcode As %Integer, message As %String) As %DynamicObject
{
    Quit ##class(sentai.catalog.TaskService).Problem($S(sqlcode = -99:403, 1:500), "SQLCODE "_sqlcode_": "_message)
}

/// The platform's create body: every field its schema requires, with the values a new %SYS.Task
/// takes by default (as the in-process path used to create it). `RunAsUser` empty → the platform
/// stores the calling operator. `Settings` are the task class's own properties.
ClassMethod TaskBody(flowId As %String, stepId As %String) As %DynamicObject
{
    Set body = {
        "Name": (..TaskName(flowId, stepId)), "RunAsUser": "", "Description": "",
        "TaskClass": "sentai.dispatch.ScheduledFlowTask", "NameSpace": ($NAMESPACE),
        "EmailOnCompletion": [], "EmailOnError": [], "EmailOnExpiration": [],
        "ExpiresDays": "", "ExpiresHours": "", "ExpiresMinutes": "",
        "OutputDirectory": "", "OutputFilename": "", "Priority": "Normal",
        "TimePeriod": "Daily", "TimePeriodDay": "", "DailyFrequency": "Once",
        "DailyFrequencyTime": "", "DailyIncrement": "", "DailyStartTime": "00:00:00",
        "DailyEndTime": "00:00:00", "StartDate": ($ZDATE(+$HOROLOG + 1, 3)), "EndDate": "",
        "RunAfterGUID": "", "MirrorStatus": "Primary"
    }
    Do body.%Set("TimePeriodEvery", 1, "number")
    For key = "EmailOutput", "OpenOutputFile", "SuspendOnError", "SuspendTerminated", "IsBatch", "RescheduleOnStart" {
        Do body.%Set(key, 0, "boolean")
    }
    Do body.%Set("Expires", 1, "boolean")
    Do body.%Set("OutputFileIsBinary", 1, "boolean")
    Set settings = {"FlowId": (flowId), "StepId": (stepId)}
    Do settings.%Set("IsRoot", '##class(sentai.rest.Dispatcher).StepHasIncomingEdge(flowId, stepId), "number")
    Do body.%Set("Settings", settings)
    Quit body
}

/// The product's task name grammar (spec 006 TaskOrigin reads it back).
ClassMethod TaskName(flowId As %String, stepId As %String) As %String
{
    Quit "SentaiTask: "_flowId_"#"_stepId
}

/// Highest platform id among the listed tasks named exactly `name` (ids only grow, so a task left
/// by an earlier schedule of the same flow is never taken for the one just created).
ClassMethod NewestIdNamed(rows As %DynamicArray, name As %String) As %String
{
    Set newest = ""
    Quit:(rows.%ClassName(1) '= "%Library.DynamicArray") ""
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.k, .row) {
        Continue:'$IsObject(row)
        Continue:(row.%Get("Name") '= name)
        Set id = row.%Get("Id")
        Continue:'##class(sentai.catalog.TaskService).IsTaskId(id)
        If (newest = "") || (+id > newest) Set newest = +id
    }
    Quit newest
}

/// Best effort: deletes, with the operator's token, the tasks this request created.
ClassMethod RollBack(taskIds As %DynamicArray, bearerToken As %String)
{
    Set iter = taskIds.%GetIterator()
    While iter.%GetNext(.k, .taskId) {
        Try {
            Do ##class(sentai.dispatch.AdminApiClient).Delete("/api/admin/v2/task?id="_(+taskId), bearerToken, .httpStatus)
        } Catch {
        }
    }
}

}
