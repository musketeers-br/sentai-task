/// The platform's Task Manager as the product reports it (spec 006). Every value comes from the
/// management API, read with the requesting operator's token (research R-1: the in-process path
/// skips the platform's task privilege). Results are outcome values `{httpStatus, body}` or
/// `{httpStatus, problem}` that sentai.rest.Dispatcher writes as they are (Constitution IV).
Class sentai.catalog.TaskService Extends %RegisteredObject
{

/// GET /catalog/tasks: list read to enumerate, then single + info per task (sequential, R-2),
/// filtered in memory on the corrected values. Envelope unchanged: {total, matched, items}.
ClassMethod List(bearerToken As %String, q As %String = "", namespace As %String = "", filter As %String = "all", destructiveOnly As %String = "0") As %DynamicObject
{
    If '##class(sentai.catalog.TaskFilter).Validate(q, namespace, filter, destructiveOnly, .problem) {
        Quit ..Problem(400, problem)
    }

    Set list = ..PlatformRead("/api/admin/v2/tasks", bearerToken)
    If (list.httpStatus '= 200) || '$IsObject(list.result) || (list.result.%ClassName(1) '= "%Library.DynamicArray") {
        Quit ..Refusal(list)
    }

    Set items = [], total = 0
    Set iter = list.result.%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Set total = total + 1
        Set id = entry.%Get("Id")
        If ..IsTaskId(id) {
            Set single = ..PlatformRead("/api/admin/v2/task?id="_(+id), bearerToken)
            Set info = ..PlatformRead("/api/admin/v2/task/info?id="_(+id), bearerToken)
        } Else {
            Set (single, info) = {"httpStatus": 0}
        }
        Set task = ##class(sentai.catalog.TaskShape).Build(id, entry, single, info)
        If ##class(sentai.catalog.TaskFilter).Matches(task, q, namespace, filter, destructiveOnly) {
            Do items.%Push(task)
        }
    }

    Set body = {"items": (items)}
    Do body.%Set("total", total, "number")
    Do body.%Set("matched", items.%Size(), "number")
    Quit ..Ok(body)
}

/// GET /catalog/tasks/{taskId}: single + info (+ history) read of one task. A non-positive-integer id is
/// "not found" without any platform call; a refused single read is the whole answer, verbatim.
ClassMethod Read(taskId As %String, bearerToken As %String) As %DynamicObject
{
    If '..IsTaskId(taskId) Quit ..Problem(404, "Task '"_taskId_"' does not exist")

    Set single = ..PlatformRead("/api/admin/v2/task?id="_(+taskId), bearerToken)
    If (single.httpStatus '= 200) || '$IsObject(single.result) Quit ..Refusal(single)
    Set info = ..PlatformRead("/api/admin/v2/task/info?id="_(+taskId), bearerToken)
    Set task = ##class(sentai.catalog.TaskShape).Build(+taskId, "", single, info)

    // Recent runs (FR-008): the item read only; the history query parameter is `taskId` (R-4).
    Set history = ""
    If task.%IsDefined("class") Set history = ..PlatformRead("/api/admin/v2/task/history?taskId="_(+taskId), bearerToken)
    Do ##class(sentai.catalog.TaskShape).AttachRecentRuns(task, history, single)

    Quit ..Ok(task)
}

/// POST /catalog/tasks/{taskId}/suspend (research R-3): the platform's suspend or resume call with
/// a JSON body `{}`, then a re-read. The platform answers 200 even when its own suspend fails, so
/// the answer is decided by the re-read: the requested state → 200 with the task; otherwise
/// 502 SUSPEND_NOT_APPLIED with the platform's info read verbatim. A refusal is verbatim, with
/// no re-read.
ClassMethod SetSuspended(taskId As %String, suspended As %Boolean, bearerToken As %String) As %DynamicObject
{
    If '..IsTaskId(taskId) Quit ..Problem(404, "Task '"_taskId_"' does not exist")

    Set path = $S(suspended:"/api/admin/v2/task/suspend", 1:"/api/admin/v2/task/resume")_"?id="_(+taskId)
    Set call = ..PlatformPost(path, {}, bearerToken)
    If (call.httpStatus < 200) || (call.httpStatus >= 300) Quit ..Refusal(call)

    Set single = ..PlatformRead("/api/admin/v2/task?id="_(+taskId), bearerToken)
    If (single.httpStatus '= 200) || '$IsObject(single.result) Quit ..Refusal(single)
    Set info = ..PlatformRead("/api/admin/v2/task/info?id="_(+taskId), bearerToken)
    Set task = ##class(sentai.catalog.TaskShape).Build(+taskId, "", single, info)

    If task.%IsDefined("suspended") && (task.suspended = ''suspended) Quit ..Ok(task)

    Set reported = $S(task.%IsDefined("suspended"):$S(task.suspended:"true", 1:"false"), 1:"unavailable")
    Set detail = "SUSPEND_NOT_APPLIED: the platform accepted the call but reports suspended="_reported
    Quit ..Problem(502, detail, $S(##class(sentai.catalog.TaskShape).IsOk(info):"", 1:info.status), $S(##class(sentai.catalog.TaskShape).IsOk(info):info.result, 1:""))
}

/// One platform call with a body, as a value {httpStatus, result, status} (see PlatformRead).
ClassMethod PlatformPost(path As %String, body As %DynamicObject, bearerToken As %String) As %DynamicObject
{
    Set call = {}, httpStatus = 0, location = "", answer = ""
    Try {
        Set answer = ##class(sentai.dispatch.AdminApiClient).Post(path, bearerToken, body, .httpStatus, .location)
    } Catch {
        Set httpStatus = 0, answer = ""
    }
    Do call.%Set("httpStatus", +httpStatus, "number")
    If $IsObject(answer) {
        If answer.%IsDefined("result") Do call.%Set("result", answer.%Get("result"))
        If $IsObject(answer.%Get("status")) Do call.%Set("status", answer.%Get("status"))
    }
    Quit call
}

/// One platform read as a value {httpStatus, result, status}. The infrastructure edge: an
/// exception from the HTTP client (platform unreachable) becomes httpStatus 0.
ClassMethod PlatformRead(path As %String, bearerToken As %String) As %DynamicObject
{
    Set read = {}, httpStatus = 0, location = "", body = ""
    Try {
        Set body = ##class(sentai.dispatch.AdminApiClient).Get(path, bearerToken, .httpStatus, .location)
    } Catch {
        Set httpStatus = 0, body = ""
    }
    Do read.%Set("httpStatus", +httpStatus, "number")
    If $IsObject(body) {
        If body.%IsDefined("result") Do read.%Set("result", body.%Get("result"))
        If $IsObject(body.%Get("status")) Do read.%Set("status", body.%Get("status"))
    }
    Quit read
}

/// A refused or failed read as the whole answer: the platform's status and its `status` object,
/// with nothing added (Constitution III). No HTTP status at all → 502 PLATFORM_UNREACHABLE.
ClassMethod Refusal(read As %DynamicObject) As %DynamicObject
{
    If (+read.httpStatus = 0) Quit ..Problem(502, "PLATFORM_UNREACHABLE: the management API did not answer")
    Set status = $S(read.httpStatus < 400:502, 1:+read.httpStatus)
    Quit ..Problem(status, ##class(sentai.catalog.TaskShape).ErrorText(read.status), read.status)
}

ClassMethod Ok(body As %DynamicObject) As %DynamicObject
{
    Set out = {"body": (body)}
    Do out.%Set("httpStatus", 200, "number")
    Quit out
}

ClassMethod Problem(httpStatus As %Integer, detail As %String, platformStatus As %DynamicObject = "", platformInfo As %DynamicObject = "") As %DynamicObject
{
    Set problem = {"title": (..Title(httpStatus)), "detail": (detail)}
    Do problem.%Set("status", httpStatus, "number")
    If $IsObject(platformStatus) Do problem.%Set("platformStatus", platformStatus)
    If $IsObject(platformInfo) Do problem.%Set("platformInfo", platformInfo)
    Set out = {"problem": (problem)}
    Do out.%Set("httpStatus", httpStatus, "number")
    Quit out
}

ClassMethod Title(httpStatus As %Integer) As %String
{
    Quit $CASE(httpStatus, 400:"Bad Request", 401:"Unauthorized", 403:"Forbidden", 404:"Not Found", 415:"Unsupported Media Type", 500:"Internal Error", 502:"Bad Gateway", :"Error")
}

ClassMethod IsTaskId(id As %String) As %Boolean
{
    Quit (id ? 1.N) && (+id > 0)
}

}
