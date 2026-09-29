/// Spec 013 US3 (FR-009): the system alerts check over the platform's dashboard, with scripted
/// answers shaped like IRIS 2026.2's (research R-1).
Class sentai.unittest.steps.ReportSystemAlertsTest Extends sentai.unittest.SentaiTestCase
{

Parameter PATH = "/api/admin/v2/monitor/dashboard/main";

ClassMethod Dashboard(serious As %Integer = 0, appErrors As %Integer = 0, lockTable As %String = "Normal") As %String
{
    Quit {"status": {"errors": [], "summary": ""}, "console": [], "result": {
        "Status": {"UpTime": "1d  8h 33m", "LastBackup": "Never", "SystemMonitor": false},
        "SystemUsage": {"DatabaseSpace": "Normal", "DatabaseJournal": "Normal", "JournalSpace": "Normal", "JournalEntries": 5154747,
                        "LockTable": (lockTable), "WriteDaemon": "Normal", "Processes": 5, "CSPSessions": 3, "BusyProcesses": [{"Process": 1}]},
        "Alerts": {"SeriousAlerts": (serious), "ApplicationErrors": (appErrors)},
        "Licensing": {"LicenseLimit": 8, "LicenseUse": 0, "LicenseUseHigh": 25}}}.%ToJSON()
}

ClassMethod Build(params As %DynamicObject = "", Output report As %DynamicObject) As %Status
{
    Set:(params = "") params = {}
    Quit ##class(sentai.dispatch.ReadExecutor).Build("system-alerts-check", params, ##class(sentai.steps.reports.Reader).For("", "tok"), .report)
}

Method TestAllNormalCompletes()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#PATH, "GET", 200, "", ..Dashboard())
    Set sc = ..Build(, .report)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertEquals(report.findings.%Size(), 0)
    Do $$$AssertEquals(report.details.alerts.serious, 0)
    Do $$$AssertEquals(report.details.systemUsage.LockTable, "Normal")
    Do $$$AssertNotTrue(report.details.systemUsage.%IsDefined("Processes"), "counters are not statuses")
    Do $$$AssertEquals(report.details.license.limit, 8)
}

Method TestSeriousAlertsOverTheDefaultThresholdFail()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#PATH, "GET", 200, "", ..Dashboard(179))
    Set sc = ..Build(, .report)
    Do $$$AssertTrue($$$ISERR(sc))
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "179 serious alerts (maximum 0)", $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(report.findings.%Get(0).rule, "SERIOUS_ALERTS_OVER")
    // A raised threshold lets it through.
    Do $$$AssertStatusOK(..Build({"maxSeriousAlerts": 200}, .report))
}

Method TestStatusNotNormalFailsUnlessSwitchedOff()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#PATH, "GET", 200, "", ..Dashboard(0, 0, "Troubled"))
    Set sc = ..Build(, .report)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "LockTable is Troubled")
    Do $$$AssertEquals(report.findings.%Get(0).item, "LockTable")
    Set params = {}
    Do params.%Set("requireNormalStatus", 0, "boolean")
    Do $$$AssertStatusOK(..Build(params, .report))
}

Method TestApplicationErrors()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#PATH, "GET", 200, "", ..Dashboard(0, 3))
    Set sc = ..Build({"maxApplicationErrors": 1}, .report)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "3 application errors (maximum 1)")
}

Method TestRefusalIsVerbatim()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#PATH, "GET", 403, "", "{""status"":{""summary"":""ERROR #822: Access Denied""}}")
    Set sc = ..Build(, .report)
    Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), "ERROR #5001: Administrative endpoint "_..#PATH_" returned HTTP 403: ERROR #822: Access Denied")
}

}
