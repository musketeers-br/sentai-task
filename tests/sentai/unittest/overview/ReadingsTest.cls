/// Spec 018 T005/T006: the seven readings — fixed paths, allow-lists at every depth, computed
/// columns, refusals verbatim, no cache.
Class sentai.unittest.overview.ReadingsTest Extends sentai.unittest.SentaiTestCase
{

Method Read(area As %String) As %DynamicObject
{
    Quit ##class(sentai.overview.Readings).Read(area, "fake-token")
}

Method TestProcessesAllowListAndShape()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set out = ..Read("processes")
    Do $$$AssertEquals(out.httpStatus, 200)
    Set r = out.body
    Do $$$AssertEquals(r.area, "processes")
    Do $$$AssertTrue(r.readAt '= "")
    Do $$$AssertEquals(r.rows.%Size(), 3)
    Do $$$AssertEquals(r.columns.%Get(0), "Pid")
    Set row = r.rows.%Get(1)
    Do $$$AssertEquals(row.Pid, 3944)
    Do $$$AssertEquals(row.Commands, 1394911)
    Do $$$AssertEquals(row.%GetTypeOf("CanBeTerminated"), "boolean")
    // A field the platform did not send is null, not 0.
    Do $$$AssertEquals(r.rows.%Get(2).%GetTypeOf("CPUTime"), "null")
    Do $$$AssertNotTrue(row.%IsDefined("CSPSessionID"))
    Do $$$AssertNotTrue(row.%IsDefined("Password"))
    Do $$$AssertNotTrue(row.%IsDefined("Nested"))
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).HitPaths(), "/api/admin/v2/processes")
}

Method TestLocksAndSessionsDropIdentifiers()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set locks = ..Read("locks").body
    Do $$$AssertEquals(locks.rows.%Size(), 2)
    Do $$$AssertNotTrue(locks.rows.%Get(0).%IsDefined("DeleteID"))
    Set sessions = ..Read("web-sessions").body
    Do $$$AssertEquals(sessions.rows.%Get(0).Username, "_SYSTEM")
    Do $$$AssertNotTrue(sessions.rows.%Get(0).%IsDefined("ID"))
}

Method TestMemoryComputesUsedPercent()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set r = ..Read("memory").body
    Do $$$AssertEquals(r.computed.%ToJSON(), "[""SMHUsedPercent""]")
    Do $$$AssertEquals(r.rows.%Get(0).%GetTypeOf("SMHUsedPercent"), "null")
    Do $$$AssertEquals(r.rows.%Get(1).SMHUsedPercent, 100)
    Do $$$AssertEquals(r.rows.%Get(3).SMHUsedPercent, 84)
}

Method TestActivityNestedAllowLists()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set r = ..Read("activity").body
    Do $$$AssertEquals(r.rows.%Get(0).Name, "Global")
    Do $$$AssertEquals(r.parts.systemUsage.BlockReads, 4869)
    Do $$$AssertEquals(r.parts.dashboard.performance.GlobalRefsPerSecond, 3841)
    Do $$$AssertEquals(r.parts.dashboard.status.UpTime, "0d  2h 16m")
    Do $$$AssertEquals(r.parts.dashboard.systemUsage.BusyProcesses.%Get(0).Process, 3944)
    Do $$$AssertNotTrue(r.parts.dashboard.%IsDefined("Alerts"))
    Do $$$AssertNotTrue(r.parts.dashboard.systemUsage.BusyProcesses.%Get(0).%IsDefined("Password"))
}

Method TestLicensesNestedAllowLists()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set r = ..Read("licenses").body
    Do $$$AssertEquals(r.rows.%Get(0).Process, "System")
    Do $$$AssertEquals(r.parts.summary.%Size(), 3)
    Do $$$AssertEquals(r.parts.byUser.%Get(0).UserId, "00")
    Do $$$AssertNotTrue(r.parts.%IsDefined("connectionList"))
    Do $$$AssertNotTrue(r.%ToJSON() [ "ServerIP")
}

Method TestNoReadingEverLeaks()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    For area = "processes", "locks", "memory", "activity", "devices", "licenses", "web-sessions" {
        Set json = ..Read(area).%ToJSON()
        Do $$$AssertNotTrue(json [ ##class(sentai.unittest.overview.OverviewFixtures).#Leak, area_" leaks nothing")
    }
}

Method TestRefusalIsVerbatim()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/locks")
    Set out = ..Read("locks")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.platformStatus.summary, "ERROR #822: Access Denied")
}

Method TestOkWithErrorsIsARefusal()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/devices", "GET", 200, "", {"status": {"errors": [{"error": "ERROR #5001: boom"}], "summary": "ERROR #5001: boom"}, "result": []}.%ToJSON())
    Set out = ..Read("devices")
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertTrue(out.problem.detail [ "boom")
}

Method TestSilentPlatformIsUnreachable()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).Silence("/api/admin/v2/processes")
    Set out = ..Read("processes")
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertTrue(out.problem.detail [ "PLATFORM_UNREACHABLE")
}

Method TestActivityRefusedAsAWhole()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/monitor/dashboard/main")
    Set out = ..Read("activity")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertNotTrue(out.%IsDefined("body"))
}

Method TestEveryRequestReadsThePlatform()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ..Read("processes"), ..Read("processes")
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).Hits("/api/admin/v2/processes"), 2)
}

Method TestUnknownReadingMakesNoCall()
{
    For area = "security", "nope", "../api/admin/info" {
        Set out = ..Read(area)
        Do $$$AssertEquals(out.httpStatus, 404)
    }
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).HitPaths(), "")
}

}
