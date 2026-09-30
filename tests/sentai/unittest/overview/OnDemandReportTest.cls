/// Spec 018 T018/T019: a report on demand is the step's own report, with no run.
Class sentai.unittest.overview.OnDemandReportTest Extends sentai.unittest.SentaiTestCase
{

Method ScriptReports()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/security/user?name=_SYSTEM", {"Name": "_SYSTEM", "Roles": ["%All"], "Enabled": true})
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/security/services", [{"Name": "%Service_Telnet", "Enabled": true, "AutheEnabled": 64}])
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/security/audit/enabled", {"Enabled": false})
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/wallet/secrets?collection=SentaiTask", [{"Name": "run-as", "Type": "password", "Value": "never"}])
}

Method Counts() As %String
{
    Set r = 0, sr = 0, le = 0
    &sql(SELECT COUNT(*) INTO :r FROM sentai_model.Run)
    &sql(SELECT COUNT(*) INTO :sr FROM sentai_model.StepRun)
    &sql(SELECT COUNT(*) INTO :le FROM sentai_model.LogEntry)
    Quit r_"/"_sr_"/"_le
}

Method TestSameFindingsAsTheStepAndNoRun()
{
    Do ..ScriptReports()
    Set before = ..Counts()
    For type = "security-posture-report", "web-app-inventory", "system-alerts-check", "secrets-inventory" {
        Set out = ##class(sentai.overview.OverviewService).RunReport(type, {}, "fake-token")
        Do $$$AssertEquals(out.httpStatus, 200, type)
        Set body = out.body
        Set sc = ##class(sentai.dispatch.ReadExecutor).Build(type, {}, ##class(sentai.steps.reports.Reader).For("", "fake-token"), .direct)
        Do $$$AssertEquals(body.state, $S($$$ISOK(sc):"completed", 1:"failed"), type_" state")
        Do $$$AssertEquals(body.failureReason, $S($$$ISOK(sc):"", 1:$SYSTEM.Status.GetErrorText(sc)), type_" reason")
        Do $$$AssertEquals(body.report.findings.%ToJSON(), direct.findings.%ToJSON(), type_" findings")
        Do $$$AssertEquals(body.report.instance, "local")
        Do $$$AssertNotTrue(body.report.%IsDefined("truncated"))
        Do $$$AssertNotTrue(out.%ToJSON() [ "never", type_" never shows a secret value")
    }
    Do $$$AssertEquals(..Counts(), before, "no run, step run or log entry")
}

Method TestNonReportTypesAreRefusedWithoutACall()
{
    For type = "integrity-check", "purge-task-history" {
        Set out = ##class(sentai.overview.OverviewService).RunReport(type, {}, "fake-token")
        Do $$$AssertEquals(out.httpStatus, 422, type)
        Do $$$AssertTrue(out.problem.detail [ "STEP_TYPE_NOT_A_REPORT")
    }
    Set out = ##class(sentai.overview.OverviewService).RunReport("nope", {}, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 404)
    Do $$$AssertTrue(out.problem.detail [ "UNKNOWN_STEP_TYPE")
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).HitPaths(), "")
}

Method TestParameterFindingsLikeAFlowStep()
{
    Set cases = [{"maxSeriousAlerts": -1}, {"maxSeriousAlerts": "x"}, {"bogus": 1}]
    Set it = cases.%GetIterator()
    While it.%GetNext(.k, .params) {
        Set out = ##class(sentai.overview.OverviewService).RunReport("system-alerts-check", params, "fake-token")
        Do $$$AssertEquals(out.httpStatus, 422, params.%ToJSON())
        Set expected = []
        Do ##class(sentai.validation.FlowValidator).DeclaredStepFindings("ondemand", "system-alerts-check", ##class(sentai.registry.StepType).GetParameterSchema("system-alerts-check"), params, ##class(sentai.registry.StepType).GetTargetClass("system-alerts-check"), expected)
        Do $$$AssertEquals(out.body.errors.%ToJSON(), expected.%ToJSON())
    }
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).HitPaths(), "")
}

Method TestRefusedReadIsAFailedReport()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/security/users")
    Set out = ##class(sentai.overview.OverviewService).RunReport("security-posture-report", {}, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertEquals(out.body.state, "failed")
    Do $$$AssertTrue(out.body.failureReason [ "ERROR #822: Access Denied")
}

}
