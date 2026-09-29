/// Spec 013 US1, US2, US4 (FR-007, FR-008, FR-010, FR-005): the security posture report, the web
/// application inventory and the secrets inventory, over scripted platform answers.
Class sentai.unittest.steps.ReportSecurityTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Ok(result) As %String
{
    Quit {"status": {"errors": [], "summary": ""}, "console": [], "result": (result)}.%ToJSON()
}

ClassMethod Script(path As %String, result, status As %Integer = 200)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(path, "GET", status, "", $S(status = 200:..Ok(result), 1:"{""status"":{""summary"":"""_result_"""}}"))
}

ClassMethod Build(type As %String, params As %DynamicObject = "", Output report As %DynamicObject) As %Status
{
    Set:(params = "") params = {}
    Quit ##class(sentai.dispatch.ReadExecutor).Build(type, params, ##class(sentai.steps.reports.Reader).For("", "tok"), .report)
}

/// Users and roles, services and audit, as IRIS 2026.2 answers them (research R-1).
Method ScriptSecurity(auditOn As %Boolean = 1)
{
    Do ..Script("/api/admin/v2/security/users", [
        {"Name": "_SYSTEM", "FullName": "SQL System Manager", "Enabled": true},
        {"Name": "ops", "FullName": "Operator", "Enabled": true},
        {"Name": "IAM", "FullName": "IAM user", "Enabled": false}])
    Do ..Script("/api/admin/v2/security/user?name=_SYSTEM", {"Enabled": true, "Roles": ["%All"], "Password": "must-not-leak", "PasswordHash": "must-not-leak", "AccountNeverExpires": true, "PasswordNeverExpires": false})
    Do ..Script("/api/admin/v2/security/user?name=ops", {"Enabled": true, "Roles": ["%Operator"], "AccountNeverExpires": false, "PasswordNeverExpires": false})
    Do ..Script("/api/admin/v2/security/services", [
        {"Name": "%Service_Login", "Enabled": true, "AuthenticationMethods": ["Password"]},
        {"Name": "%Service_Weblink", "Enabled": false, "AuthenticationMethods": ["Unauthenticated"]},
        {"Name": "%Service_Open", "Enabled": true, "AuthenticationMethods": ["Password", "Unauthenticated"]}])
    Set audit = {}
    Do audit.%Set("Enabled", auditOn, "boolean")
    Do ..Script("/api/admin/v2/security/audit/enabled", audit)
}

Method TestSecurityFindings()
{
    Do ..ScriptSecurity(0)
    Set sc = ..Build("security-posture-report", , .report)
    Do $$$AssertStatusOK(sc)
    Set rules = ""
    Set it = report.findings.%GetIterator()
    While it.%GetNext(.k, .f) { Set rules = rules_f.rule_":"_f.item_"," }
    Do $$$AssertTrue(rules [ "ALL_ROLE_HOLDER:_SYSTEM,", rules)
    Do $$$AssertTrue(rules [ "UNAUTHENTICATED_SERVICE:%Service_Open,", "enabled service only")
    Do $$$AssertNotTrue(rules [ "%Service_Weblink", "a disabled service is not a finding")
    Do $$$AssertTrue(rules [ "AUDIT_DISABLED:audit,")
    Do $$$AssertEquals(report.summary.high, 2)
    Do $$$AssertEquals(report.details.accounts.%Size(), 2, "enabled accounts only")
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak", "no password field is ever copied (FR-005)")
}

Method TestFailOnFindingsKeepsTheReport()
{
    Do ..ScriptSecurity(1)
    Set params = {}
    Do params.%Set("failOnFindings", 1, "boolean")
    Set sc = ..Build("security-posture-report", params, .report)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "1 high finding: ALL_ROLE_HOLDER _SYSTEM", $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertTrue($IsObject(report) && (report.findings.%Size() > 0), "the report is kept")
}

Method TestOneRoleReadRefusedIsAFinding()
{
    Do ..ScriptSecurity(1)
    Do ..Script("/api/admin/v2/security/user?name=ops", "ERROR #822: Access Denied", 403)
    Do $$$AssertStatusOK(..Build("security-posture-report", , .report))
    Do $$$AssertTrue(report.%ToJSON() [ "ROLES_NOT_READABLE")
}

Method TestEveryRoleReadRefusedFails()
{
    Do ..ScriptSecurity(1)
    Do ..Script("/api/admin/v2/security/user?name=ops", "ERROR #822: Access Denied", 403)
    Do ..Script("/api/admin/v2/security/user?name=_SYSTEM", "ERROR #822: Access Denied", 403)
    Set sc = ..Build("security-posture-report", , .report)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "returned HTTP 403: ERROR #822: Access Denied")
}

Method TestUserListRefusedFailsVerbatim()
{
    Do ..Script("/api/admin/v2/security/users", "ERROR #822: Access Denied", 403)
    Set sc = ..Build("security-posture-report", , .report)
    Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), "ERROR #5001: Administrative endpoint /api/admin/v2/security/users returned HTTP 403: ERROR #822: Access Denied")
}

Method TestWebAppFindings()
{
    Do ..Script("/api/admin/v2/web-apps", [
        {"Name": "/api/monitor", "Namespace": "%SYS", "Enabled": true, "Type": "CSP", "Resource": "", "AuthenticationMethods": ["Unauthenticated"], "IsSystemApp": false, "DispatchClass": "%Api.Monitor"},
        {"Name": "/csp/sentai", "Namespace": "IRISAPP", "Enabled": true, "Type": "CSP", "Resource": "", "AuthenticationMethods": ["Unauthenticated"], "IsSystemApp": false, "DispatchClass": "sentai.web.StaticFiles"},
        {"Name": "/csp/user", "Namespace": "USER", "Enabled": true, "Type": "CSP", "Resource": "", "AuthenticationMethods": ["Unauthenticated", "Password"], "IsSystemApp": false, "DispatchClass": ""},
        {"Name": "/csp/sys", "Namespace": "%SYS", "Enabled": true, "Type": "System,CSP", "Resource": "", "AuthenticationMethods": ["Unauthenticated", "Password"], "IsSystemApp": false, "DispatchClass": ""},
        {"Name": "/api/closed", "Namespace": "USER", "Enabled": false, "Type": "CSP", "Resource": "", "AuthenticationMethods": ["Unauthenticated"], "IsSystemApp": false, "DispatchClass": "X"},
        {"Name": "/api/guarded", "Namespace": "USER", "Enabled": true, "Type": "CSP", "Resource": "%Guard", "AuthenticationMethods": ["Unauthenticated"], "IsSystemApp": false, "DispatchClass": "Y"},
        {"Name": "/csp/sentai/api/v1", "Namespace": "IRISAPP", "Enabled": true, "Type": "CSP", "Resource": "", "AuthenticationMethods": ["Password"], "IsSystemApp": false, "DispatchClass": "sentai.rest.Dispatcher"}])
    Do $$$AssertStatusOK(..Build("web-app-inventory", , .report))
    Set rules = ""
    Set it = report.findings.%GetIterator()
    While it.%GetNext(.k, .f) { Set rules = rules_f.rule_":"_f.item_"," }
    Do $$$AssertEquals(rules, "ANONYMOUS_REST_ENDPOINT:/api/monitor,ANONYMOUS_REST_ENDPOINT:/csp/sentai,ANONYMOUS_APPLICATION:/csp/user,")
    Do $$$AssertEquals(report.details.applications.%Size(), 7)
}

Method TestSecretsNeverCarryValues()
{
    Do ..Script("/api/admin/v2/wallet/collections", [{"Name": "Ops", "UseResource": "%Ops", "EditResource": "%Ops"}, {"Name": "Open", "UseResource": "", "EditResource": ""}])
    Do ..Script("/api/admin/v2/wallet/secrets?collection=Ops", [{"Name": "Ops.db", "Type": "KeyValue", "Secret": "must-not-leak", "Value": "must-not-leak"}])
    Do ..Script("/api/admin/v2/wallet/secrets?collection=Open", [])
    Do $$$AssertStatusOK(..Build("secrets-inventory", , .report))
    Do $$$AssertEquals(report.details.collections.%Get(0).secrets.%Get(0).name, "Ops.db")
    Do $$$AssertEquals(report.details.collections.%Get(0).secrets.%Get(0).type, "KeyValue")
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak", "no secret value (FR-005, FR-010)")
    Do $$$AssertEquals(report.findings.%Size(), 1)
    Do $$$AssertEquals(report.findings.%Get(0).rule_":"_report.findings.%Get(0).item, "UNPROTECTED_COLLECTION:Open")
}

Method TestEmptyWallet()
{
    Do ..Script("/api/admin/v2/wallet/collections", [])
    Do $$$AssertStatusOK(..Build("secrets-inventory", , .report))
    Do $$$AssertEquals(report.details.collections.%Size(), 0)
}

}
