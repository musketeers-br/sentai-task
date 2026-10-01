/// Spec 018 US5: suspend, resume and terminate a process through the platform, with the contract
/// the T029 spike recorded (evidence/01–04): `POST /api/admin/v2/process/<action>?id=<pid>` with
/// no body; a body instead of `?id=` is refused 400. The platform decides every action — the
/// product keeps no list of protected processes. Terminate needs the pid typed again (FR-021).
Class sentai.overview.ProcessActions Extends %RegisteredObject
{

Parameter ACTIONS = ",suspend,resume,terminate,";

/// Outcome `{httpStatus, body|problem}`. 404 unknown action, 400 bad pid, 428 missing or wrong
/// confirmation (no platform call, no record); otherwise the platform's answer, recorded.
ClassMethod Act(pid As %String, action As %String, confirmation As %String, user As %String, token As %String) As %DynamicObject
{
    Quit:((action = "") || (..#ACTIONS '[ (","_action_","))) ##class(sentai.catalog.TaskService).Problem(404, "UNKNOWN_PROCESS_ACTION: '"_action_"' is not suspend, resume or terminate")
    Quit:'((pid ? 1.N) && (+pid > 0)) ##class(sentai.catalog.TaskService).Problem(400, "INVALID_PID: the process id must be a positive integer")
    If (action = "terminate") && (confirmation '= pid) {
        Set out = ##class(sentai.catalog.TaskService).Problem(428, "CONFIRMATION_REQUIRED: terminating process "_pid_" requires the process id typed as confirmation")
        Set out.problem.title = "Confirmation Required"
        Quit out
    }
    Set call = ##class(sentai.catalog.TaskService).PlatformPost("/api/admin/v2/process/"_action_"?id="_(+pid), "", token)
    Set accepted = ((call.httpStatus >= 200) && (call.httpStatus < 300) && '##class(sentai.overview.Readings).HasErrors(call.status))
    Do ##class(sentai.model.ProcessAction).Record(user, +pid, action, +call.httpStatus, accepted, call.status)
    If 'accepted {
        Set out = ##class(sentai.catalog.TaskService).Refusal(call)
        Set:(out.problem.detail = "") out.problem.detail = "HTTP "_(+call.httpStatus)_": no reason given"
        Quit out
    }
    Set body = {"pid": (+pid), "action": (action), "platform": {"httpStatus": (+call.httpStatus)}}
    Do:$IsObject(call.status) body.platform.%Set("status", call.status)
    Set process = ..ReRead(+pid, token)
    Do body.%Set("process", process, $S($IsObject(process):"", 1:"null"))
    Quit ##class(sentai.catalog.TaskService).Ok(body)
}

/// The process as the platform reports it now, allow-listed (no CSPSessionID, research R-4), or
/// null when it no longer exists.
ClassMethod ReRead(pid As %Integer, token As %String)
{
    Set read = ##class(sentai.catalog.TaskService).PlatformRead("/api/admin/v2/process?id="_pid, token)
    Quit:##class(sentai.overview.Readings).IsRefused(read) ""
    Quit ##class(sentai.overview.Readings).Row(read.result, "Pid,UserName,NameSpace,Routine,State,CommandsExecuted,GlobalReferences,CPUTime,CanBeSuspended,CanBeTerminated")
}

/// The newest `limit` records (1..200), newest first.
ClassMethod List(limit As %Integer = 50) As %DynamicArray
{
    Set limit = $S((limit ? 1.N) && (+limit >= 1) && (+limit <= 200):+limit, 1:50)
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP ? ID, actedAt, operatorName, pid, processAction, httpStatus, accepted, platformStatus FROM sentai_model.ProcessAction ORDER BY ID DESC", limit)
    While rs.%Next() {
        Set rec = {"id": (rs.%Get("ID")), "at": (rs.%Get("actedAt")), "operator": (rs.%Get("operatorName")), "pid": (+rs.%Get("pid")), "action": (rs.%Get("processAction"))}
        Do rec.%Set("httpStatus", +rs.%Get("httpStatus"), "number")
        Do rec.%Set("accepted", +rs.%Get("accepted"), "boolean")
        Set ps = rs.%Get("platformStatus")
        Do rec.%Set("platformStatus", $S(ps '= "":##class(%DynamicAbstractObject).%FromJSON(ps), 1:""), $S(ps '= "":"", 1:"null"))
        Do out.%Push(rec)
    }
    Quit out
}

}
