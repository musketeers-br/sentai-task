/// Spec 018: platform answers shaped like the 2026-09-29 probe (research R-1), for the overview
/// tests. `Leak` is a marker that must never appear in any overview answer (SC-006); every answer
/// carries it in fields no allow-list names, at the top level and inside nested objects.
Class sentai.unittest.overview.OverviewFixtures Extends %RegisteredObject
{

Parameter Leak = "LEAKED-SECRET-7f3a";

ClassMethod Wrap(result) As %String
{
    Quit {"status": {"errors": [], "summary": ""}, "console": [], "result": (result)}.%ToJSON()
}

ClassMethod Script(path As %String, result)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(path, "GET", 200, "", ..Wrap(result))
}

/// Adds the leak fields to `obj`.
ClassMethod Taint(obj As %DynamicObject) As %DynamicObject
{
    For f = "Password", "PasswordHash", "access_token", "ID", "DeleteID", "CSPSessionID", "Value" { Do obj.%Set(f, ..#Leak) }
    Do obj.%Set("Nested", {"Password": (..#Leak)})
    Quit obj
}

ClassMethod Processes() As %DynamicArray
{
    Set list = []
    Do list.%Push(..Taint({"Job": 1, "Pid": 839, "Username": "", "Nspace": "", "Routine": "CONTROL", "Commands": 0, "Globals": 0, "State": "RUN", "CPUTime": 340, "CanBeTerminated": false}))
    Do list.%Push(..Taint({"Job": 2, "Pid": 3944, "Username": "_SYSTEM", "Nspace": "IRISAPP", "Routine": "%SYS.WorkQueueMgr", "Commands": 1394911, "Globals": 5000, "State": "RUNW", "CPUTime": 9000, "CanBeTerminated": true}))
    Do list.%Push(..Taint({"Job": 3, "Pid": 4100, "Username": "_SYSTEM", "Nspace": "USER", "Routine": "shell", "Commands": 12, "Globals": 3, "State": "READ"}))
    Quit list
}

ClassMethod Locks() As %DynamicArray
{
    Quit [(..Taint({"Pid": 4867, "ModeCount": "Exclusive", "Reference": "CleanDeletedRtn", "Directory": "/usr/irissys/mgr/", "Removable": true, "RoutineInfo": "+123^CLNDMN"})), (..Taint({"Pid": 839, "ModeCount": "Shared", "Reference": "^X(1)", "Directory": "/usr/irissys/mgr/", "Removable": false}))]
}

ClassMethod Memory() As %DynamicArray
{
    Quit [
        (..Taint({"Description": "Miscellaneous", "SMHAllocated": 0, "SMHAvailable": 0, "SMHUsed": 0, "SMTUsed": 0, "GSTUsed": 0, "AllUsed": 0})),
        (..Taint({"Description": "Security System", "SMHAllocated": 65536, "SMHAvailable": 0, "SMHUsed": 65536, "SMTUsed": 33904, "GSTUsed": 0, "AllUsed": 99440})),
        (..Taint({"Description": "Lock Table", "SMHAllocated": 262144, "SMHAvailable": 238336, "SMHUsed": 23808, "SMTUsed": 1280, "GSTUsed": 0, "AllUsed": 25088})),
        (..Taint({"Description": "Total", "SMHAllocated": 3342336, "SMHAvailable": 533196, "SMHUsed": 2809140, "SMTUsed": 1077329, "GSTUsed": 35144, "AllUsed": 3921613}))
    ]
}

ClassMethod SystemUsage() As %DynamicObject
{
    Quit ..Taint({"AllGlobalReferences": 35254564, "BlockReads": 4869, "BlockWrites": 6051, "JournalEntries": 640216, "LastUpdate": "2026-09-29 20:08:21"})
}

ClassMethod Dashboard() As %DynamicObject
{
    Quit ..Taint({
        "Performance": (..Taint({"GlobalRefsPerSecond": 3841, "GlobalRefs": 97749739, "DiskReads": 15134, "CacheEfficiency": 2965.62})),
        "Status": (..Taint({"UpTime": "0d  2h 16m", "LastBackup": "Never", "SystemMonitor": false})),
        "SystemUsage": (..Taint({"DatabaseSpace": "Normal", "LockTable": "Normal", "Processes": 5, "CSPSessions": 1,
            "BusyProcesses": [(..Taint({"Process": 3944, "Commands": 1394911})), {"Process": "", "Commands": 0}, {"Process": "", "Commands": 0}]})),
        "Alerts": {"SeriousAlerts": 7, "ApplicationErrors": 0},
        "Licensing": {"LicenseLimit": 8, "LicenseUse": 13, "LicenseUseHigh": 25}
    })
}

ClassMethod Seizes() As %DynamicArray
{
    Quit [(..Taint({"Name": "Global", "Seize": 10, "Nseize": 2, "Aseize": 0, "Bseize": 0, "BusySet": 0}))]
}

ClassMethod Licenses() As %DynamicObject
{
    Quit ..Taint({
        "UsageByProcess": [(..Taint({"PID": 839, "Process": "System", "LID": "", "LU": 0}))],
        "UsageByUser": [(..Taint({"UserId": "00", "Type": "User", "Connects": 1, "LU": 1}))],
        "ConnectionList": [(..Taint({"UserId": "00", "ServerIP": "127.0.0.1"}))],
        "Summary": [
            {"LicenseUnitUse": "Current License Units Used ", "Local": "1", "Distributed": "Not connected to license server"},
            {"LicenseUnitUse": "Maximum License Units Used ", "Local": "2", "Distributed": "Not connected to license server"},
            {"LicenseUnitUse": "License Units   Authorized ", "Local": "8", "Distributed": "Not connected to license server"}
        ]
    })
}

ClassMethod Devices() As %DynamicArray
{
    Quit [(..Taint({"Name": "0", "PhysicalDevice": "0", "Type": "TRM", "SubType": "C-IRIS Terminal", "Description": "Principal device"})), (..Taint({"Name": "2", "Type": "SPL"}))]
}

ClassMethod WebSessions() As %DynamicArray
{
    Quit [(..Taint({"Username": "_SYSTEM", "Application": "/api/atelier/", "Timeout": "2026-09-29 20:42:58", "LicenseId": "_SYSTEM@172.21.0.1", "Preserve": 0, "AllowEndSession": true}))]
}

ClassMethod Users() As %DynamicArray
{
    Quit [(..Taint({"Name": "_SYSTEM", "Enabled": true})), (..Taint({"Name": "Admin", "Enabled": true})), (..Taint({"Name": "old", "Enabled": false}))]
}

ClassMethod WebApps() As %DynamicArray
{
    Quit [(..Taint({"Name": "/csp/sentai/api"})), (..Taint({"Name": "/api/atelier"}))]
}

ClassMethod Collections() As %DynamicArray
{
    Quit [(..Taint({"Name": "SentaiTask", "UseResource": "SentaiSchedule"}))]
}

/// Every read the overview makes, answered OK.
ClassMethod ScriptAll()
{
    Do ..Script("/api/admin/v2/processes", ..Processes())
    Do ..Script("/api/admin/v2/locks", ..Locks())
    Do ..Script("/api/admin/v2/monitor/system-usage/shared-memory", ..Memory())
    Do ..Script("/api/admin/v2/monitor/system-usage", ..SystemUsage())
    Do ..Script("/api/admin/v2/monitor/dashboard/main", ..Dashboard())
    Do ..Script("/api/admin/v2/monitor/dashboard/system-resources", ..Seizes())
    Do ..Script("/api/admin/v2/monitor/license-usage", ..Licenses())
    Do ..Script("/api/admin/v2/devices", ..Devices())
    Do ..Script("/api/admin/v2/web-sessions", ..WebSessions())
    Do ..Script("/api/admin/v2/security/users", ..Users())
    Do ..Script("/api/admin/v2/web-apps", ..WebApps())
    Do ..Script("/api/admin/v2/wallet/collections", ..Collections())
}

ClassMethod Refuse(path As %String, httpStatus As %Integer = 403, summary As %String = "ERROR #822: Access Denied")
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(path, "GET", httpStatus, "", {"status": {"errors": [{"error": (summary), "code": 822}], "summary": (summary)}, "console": [], "result": {}}.%ToJSON())
}

ClassMethod Silence(path As %String)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(path, "GET", 0, "", "")
}

ClassMethod Hits(path As %String) As %Integer
{
    Quit +$G(^sentaiTestDouble("getcount", path))
}

/// Every platform path read during the test, as a comma-separated sorted list.
ClassMethod HitPaths() As %String
{
    Set out = "", p = ""
    For { Set p = $O(^sentaiTestDouble("getcount", p))  Quit:(p = "")  Set out = out_$S(out = "":"", 1:",")_p }
    Quit out
}

}
