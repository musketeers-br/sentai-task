/// Spec 020 T004: the report helpers the security inventory steps share.
Class sentai.unittest.steps.ReportHelpersTest Extends sentai.unittest.SentaiTestCase
{

Method TestDaysLeft()
{
    Set R = "sentai.steps.reports.Report"
    Do $$$AssertEquals($CLASSMETHOD(R, "DaysLeft", "2026-09-29 10:00:00", "2026-10-09 09:00:00"), 10)
    Do $$$AssertEquals($CLASSMETHOD(R, "DaysLeft", "2026-09-29 10:00:00", "2026-09-29 23:00:00"), 0)
    Do $$$AssertEquals($CLASSMETHOD(R, "DaysLeft", "2026-09-29 10:00:00", "2026-09-20 10:00:00"), -9)
    Do $$$AssertEquals($CLASSMETHOD(R, "DaysLeft", "2026-09-29 10:00:00", "not a date"), "")
}

Method TestFindingHelpersAndAsOf()
{
    Set report = ##class(sentai.steps.reports.Report).NewReport("x")
    Do $$$AssertTrue(report.summary.asOf ? 4N1"-"2N1"-"2N1" "2N1":"2N1":"2N)
    Do ##class(sentai.steps.reports.Report).AddIncompleteRead(report, "roles", "Administrative endpoint /x returned HTTP 403")
    Do ##class(sentai.steps.reports.Report).AddNotAllRead(report, "roles", 3)
    Do $$$AssertEquals(report.summary.medium, 1)
    Do $$$AssertEquals(report.summary.info, 1)
    Do $$$AssertEquals(report.summary.itemsOmitted, 3)
    Do $$$AssertEquals(report.findings.%Get(0).rule, "INCOMPLETE_READ")
    Do $$$AssertEquals(report.findings.%Get(0).detail, "Administrative endpoint /x returned HTTP 403")
    Do $$$AssertEquals(report.findings.%Get(1).rule, "NOT_ALL_READ")
}

Method TestInsecureAddress()
{
    Set R = "sentai.steps.reports.Report"
    Do $$$AssertNotTrue($CLASSMETHOD(R, "IsInsecureAddress", "https://issuer.example/oauth2"))
    Do $$$AssertTrue($CLASSMETHOD(R, "IsInsecureAddress", "http://issuer.example/oauth2"))
    Do $$$AssertNotTrue($CLASSMETHOD(R, "IsInsecureAddress", "http://localhost:52773/csp/sys"))
    Do $$$AssertNotTrue($CLASSMETHOD(R, "IsInsecureAddress", "http://127.0.0.1/cb"))
    Do $$$AssertNotTrue($CLASSMETHOD(R, "IsInsecureAddress", "http://[::1]:8080/cb"))
    Do $$$AssertNotTrue($CLASSMETHOD(R, "IsInsecureAddress", ""))
}

/// T006: the platform's error id comes with the refusal.
Method TestReaderGivesTheErrorId()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/security/oauth2/server", "GET", 404, "", {"status": {"errors": [{"error": "ERROR #8864: OAuth 2.0 server is not configured.", "code": 8864, "id": "OAuth2NoConfiguration"}], "summary": "ERROR #8864: OAuth 2.0 server is not configured."}}.%ToJSON())
    Set reader = ##class(sentai.steps.reports.Reader).For("", "tok")
    Set result = reader.Get("/api/admin/v2/security/oauth2/server", .problem, .errorId)
    Do $$$AssertEquals(errorId, "OAuth2NoConfiguration")
    Do $$$AssertTrue(problem [ "ERROR #8864")
}

}
