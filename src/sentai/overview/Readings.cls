/// Spec 018 US1 (plan D-2, data-model §2): the seven instance readings. Each reading is fixed
/// platform paths in this class, read at request time with the operator's own token, and only
/// allow-listed fields are copied — at every depth — so a password, a session id or a field the
/// platform adds later never leaves the product (FR-016, research R-4). Values the product
/// computes are arithmetic over the same answer and are named in `computed`.
Class sentai.overview.Readings Extends %RegisteredObject
{

Parameter PROCESSFIELDS = "Pid,Job,Username,OSUserName,Nspace,Routine,State,Commands,Globals,CPUTime,ElapsedTime,Device,ClientName,IPAddress,EXEname,ParentPid,CanBeExamined,CanBeSuspended,CanBeTerminated,CanReceiveBroadcast";

Parameter LOCKFIELDS = "Pid,ModeCount,Reference,Directory,System,Removable,RemoteOwner,RoutineInfo,OSUserName";

Parameter MEMORYFIELDS = "Description,SMHAllocated,SMHAvailable,SMHUsed,SMTUsed,GSTUsed,AllUsed";

Parameter DEVICEFIELDS = "Name,PhysicalDevice,Type,SubType,Description,Alias,AlternateDevice";

Parameter SESSIONFIELDS = "Username,Application,Timeout,Preserve,LicenseId,SesProcessId,AllowEndSession";

Parameter SEIZEFIELDS = "Name,Seize,Nseize,Aseize,Bseize,BusySet";

Parameter SYSTEMUSAGEFIELDS = "AllGlobalReferences,GlobalUpdateReferences,RoutineCalls,RoutineBufferLoadsAndSaves,LogicalBlockRequests,BlockReads,BlockWrites,WIJwrites,JournalEntries,JournalBlockWrites,RoutineLines,LastUpdate";

Parameter PERFORMANCEFIELDS = "GlobalRefsPerSecond,GlobalRefs,GlobalSetKill,RoutineRefs,LogicalRequests,DiskReads,DiskWrites,CacheEfficiency";

Parameter STATUSFIELDS = "UpTime,LastBackup,SystemMonitor";

Parameter DASHUSAGEFIELDS = "DatabaseSpace,DatabaseJournal,JournalSpace,JournalEntries,LockTable,WriteDaemon,Processes,CSPSessions";

Parameter LICENSEPROCESSFIELDS = "PID,Process,LID,Type,Con,MaxCon,CSPCon,LU,Active,Grace";

Parameter LICENSEUSERFIELDS = "UserId,Type,Connects,MaxCon,CSPCon,LU,Active,Grace";

Parameter LICENSESUMMARYFIELDS = "LicenseUnitUse,Local,Distributed";

/// `area` must be one of the seven readings (the caller checks `Areas.IsReading`). Returns an
/// outcome `{httpStatus, body}` or `{httpStatus, problem}` (TaskService's shape, Constitution IV).
ClassMethod Read(area As %String, token As %String) As %DynamicObject
{
    Quit:'##class(sentai.overview.Areas).IsReading(area) ##class(sentai.catalog.TaskService).Problem(404, "UNKNOWN_READING: '"_area_"' is not an overview reading")
    Set refusal = "", reading = ""
    If (area = "processes") {
        Set reading = ..Simple(area, "/api/admin/v2/processes", ..#PROCESSFIELDS, token, .refusal)
    } ElseIf (area = "locks") {
        Set reading = ..Simple(area, "/api/admin/v2/locks", ..#LOCKFIELDS, token, .refusal)
    } ElseIf (area = "memory") {
        Set reading = ..Memory(token, .refusal)
    } ElseIf (area = "activity") {
        Set reading = ..Activity(token, .refusal)
    } ElseIf (area = "devices") {
        Set reading = ..Simple(area, "/api/admin/v2/devices", ..#DEVICEFIELDS, token, .refusal)
    } ElseIf (area = "licenses") {
        Set reading = ..Licenses(token, .refusal)
    } ElseIf (area = "web-sessions") {
        Set reading = ..Simple(area, "/api/admin/v2/web-sessions", ..#SESSIONFIELDS, token, .refusal)
    }
    Quit:$IsObject(refusal) refusal
    Quit ##class(sentai.catalog.TaskService).Ok(reading)
}

/// One platform read. Returns its `result`, or "" with `refusal` set to the outcome to answer
/// (httpStatus 0 → 502 PLATFORM_UNREACHABLE; a 200 carrying `status.errors` is a refusal).
ClassMethod Fetch(path As %String, token As %String, Output refusal As %DynamicObject)
{
    Set refusal = ""
    Set read = ##class(sentai.catalog.TaskService).PlatformRead(path, token)
    If ..IsRefused(read) {
        Set refusal = ##class(sentai.catalog.TaskService).Refusal(read)
        Set:(refusal.problem.detail = "") refusal.problem.detail = "HTTP "_(+read.httpStatus)_": no reason given"
        Quit ""
    }
    Quit read.result
}

/// A read the platform did not answer, refused, or answered with errors in its status object.
ClassMethod IsRefused(read As %DynamicObject) As %Boolean
{
    Quit:(+read.httpStatus '= 200) 1
    Quit ..HasErrors(read.status)
}

/// Whether a platform `status` object lists errors.
ClassMethod HasErrors(status) As %Boolean
{
    Quit $IsObject(status) && $IsObject(status.errors) && (status.errors.%Size() > 0)
}

ClassMethod NewReading(area As %String, fields As %String) As %DynamicObject
{
    Set columns = []
    For i = 1:1:$L(fields, ",") { Do columns.%Push($P(fields, ",", i)) }
    Quit {"area": (area), "readAt": ($ZDATETIME($HOROLOG, 3)), "columns": (columns), "rows": [], "computed": []}
}

ClassMethod Simple(area As %String, path As %String, fields As %String, token As %String, Output refusal) As %DynamicObject
{
    Set result = ..Fetch(path, token, .refusal)
    Quit:$IsObject(refusal) ""
    Set reading = ..NewReading(area, fields)
    Set reading.rows = ..Rows(result, fields)
    Quit reading
}

ClassMethod Memory(token As %String, Output refusal) As %DynamicObject
{
    Set result = ..Fetch("/api/admin/v2/monitor/system-usage/shared-memory", token, .refusal)
    Quit:$IsObject(refusal) ""
    Set reading = ..NewReading("memory", ..#MEMORYFIELDS)
    Do reading.columns.%Push("SMHUsedPercent")
    Do reading.computed.%Push("SMHUsedPercent")
    Set rows = ..Rows(result, ..#MEMORYFIELDS)
    Set it = rows.%GetIterator()
    While it.%GetNext(.k, .row) { Do ..SetPercent(row, "SMHUsedPercent", row.SMHUsed, row.SMHAllocated) }
    Set reading.rows = rows
    Quit reading
}

/// `name` = round(used / allocated × 100, 1) when allocated > 0, else null.
ClassMethod SetPercent(obj As %DynamicObject, name As %String, used, allocated)
{
    If ($ISVALIDNUM(allocated) && (+allocated > 0) && $ISVALIDNUM(used)) {
        Do obj.%Set(name, +$FN(used / allocated * 100, "", 1), "number")
    } Else {
        Do obj.%Set(name, "", "null")
    }
}

ClassMethod Activity(token As %String, Output refusal) As %DynamicObject
{
    Set usage = ..Fetch("/api/admin/v2/monitor/system-usage", token, .refusal)
    Quit:$IsObject(refusal) ""
    Set dash = ..Fetch("/api/admin/v2/monitor/dashboard/main", token, .refusal)
    Quit:$IsObject(refusal) ""
    Set seizes = ..Fetch("/api/admin/v2/monitor/dashboard/system-resources", token, .refusal)
    Quit:$IsObject(refusal) ""
    Set reading = ..NewReading("activity", ..#SEIZEFIELDS)
    Set reading.rows = ..Rows(seizes, ..#SEIZEFIELDS)
    Set reading.parts = {"systemUsage": (..Row(usage, ..#SYSTEMUSAGEFIELDS)), "dashboard": (..Dashboard(dash))}
    Quit reading
}

/// The allow-listed view of dashboard/main used by `activity`.
ClassMethod Dashboard(dash) As %DynamicObject
{
    Set d = $S($IsObject(dash):dash, 1:{})
    Set usage = ..Row(d.SystemUsage, ..#DASHUSAGEFIELDS)
    Set busy = []
    If $IsObject(d.SystemUsage) && $IsObject(d.SystemUsage.BusyProcesses) {
        Set it = d.SystemUsage.BusyProcesses.%GetIterator()
        While it.%GetNext(.k, .p) { Do busy.%Push(..Row(p, "Process,Commands")) }
    }
    Set usage.BusyProcesses = busy
    Quit {"performance": (..Row(d.Performance, ..#PERFORMANCEFIELDS)), "status": (..Row(d.Status, ..#STATUSFIELDS)), "systemUsage": (usage)}
}

ClassMethod Licenses(token As %String, Output refusal) As %DynamicObject
{
    Set result = ..Fetch("/api/admin/v2/monitor/license-usage", token, .refusal)
    Quit:$IsObject(refusal) ""
    Set l = $S($IsObject(result):result, 1:{})
    Set reading = ..NewReading("licenses", ..#LICENSEPROCESSFIELDS)
    Set reading.rows = ..Rows(l.UsageByProcess, ..#LICENSEPROCESSFIELDS)
    Set reading.parts = {"summary": (..Rows(l.Summary, ..#LICENSESUMMARYFIELDS)), "byUser": (..Rows(l.UsageByUser, ..#LICENSEUSERFIELDS))}
    Quit reading
}

/// Each object of the array `list` through `Row`; anything that is not an array gives [].
ClassMethod Rows(list, fields As %String) As %DynamicArray
{
    Set out = []
    Quit:'$IsObject(list) out
    Quit:(list.%ClassName(1) '= "%Library.DynamicArray") out
    Set it = list.%GetIterator()
    While it.%GetNext(.k, .row) { Do out.%Push(..Row(row, fields)) }
    Quit out
}

/// Exactly the `fields` (comma-separated) of `source`, with their JSON types; a field the source
/// lacks is null, never 0 (edge case). Nested objects or arrays are never copied here: a caller
/// that needs one names its own allow-list (data-model §2, "nested objects follow the same rule").
ClassMethod Row(source, fields As %String) As %DynamicObject
{
    Set out = {}, has = $IsObject(source) && (source.%ClassName(1) = "%Library.DynamicObject")
    For i = 1:1:$L(fields, ",") {
        Set f = $P(fields, ",", i)
        If 'has || 'source.%IsDefined(f) { Do out.%Set(f, "", "null")  Continue }
        Set type = source.%GetTypeOf(f)
        If (type = "object") || (type = "array") || (type = "null") || (type = "unassigned") {
            Do out.%Set(f, "", "null")
        } ElseIf (type = "boolean") {
            Do out.%Set(f, source.%Get(f), "boolean")
        } ElseIf (type = "number") {
            Do out.%Set(f, source.%Get(f), "number")
        } Else {
            Do out.%Set(f, source.%Get(f))
        }
    }
    Quit out
}

}
