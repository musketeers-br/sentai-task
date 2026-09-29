/// Spec 020 US2 (FR-007): the permissions inventory over scripted platform answers.
Class sentai.unittest.steps.ReportPermissionsInventoryTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Script(path As %String, result, status As %Integer = 200)
{
    Do ##class(sentai.unittest.steps.ReportCertificateExpiryTest).Script(path, result, status)
}

ClassMethod Build(params As %DynamicObject = "", Output report As %DynamicObject) As %Status
{
    Set:(params = "") params = {}
    Quit ##class(sentai.dispatch.ReadExecutor).Build("permissions-inventory", params, ##class(sentai.steps.reports.Reader).For("", "tok"), .report)
}

ClassMethod ScriptInstance()
{
    Do ..Script("roles", [{"Name": "%All", "Description": "Superuser"}, {"Name": "%Developer", "Description": "Devs"}, {"Name": "Shadow", "Description": "grants everything"}])
    Do ..Script("role?name=%25All", {"Resources": [], "GrantedRoles": []})
    Do ..Script("role?name=%25Developer", {"Resources": [{"Name": "%DB_USER", "Permissions": "RW"}, {"Name": "%Development", "Permissions": "U"}], "GrantedRoles": [], "Password": "must-not-leak"})
    Do ..Script("role?name=Shadow", {"Resources": [], "GrantedRoles": ["%All"]})
    Do ..Script("resources", [
        {"Name": "%DB_IRISLIB", "PublicPermission": "R", "ResourceType": "Database"},
        {"Name": "%DB_OPEN", "PublicPermission": "RW", "ResourceType": "Database"},
        {"Name": "%Admin_Manage", "PublicPermission": "U", "ResourceType": "System"},
        {"Name": "%Service_Open", "PublicPermission": "U", "ResourceType": "Service"},
        {"Name": "%Development", "PublicPermission": "", "ResourceType": "System"}])
}

ClassMethod Rules(report As %DynamicObject) As %String
{
    Quit ##class(sentai.unittest.steps.ReportCertificateExpiryTest).Rules(report)
}

Method TestInventoryAndRules()
{
    Do ..ScriptInstance()
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertEquals(report.details.roles.%Size(), 3)
    Do $$$AssertEquals(report.details.resources.%Size(), 5)
    Do $$$AssertEquals(report.summary.roles, 3)
    Do $$$AssertEquals(report.summary.resources, 5)
    Set dev = report.details.roles.%Get(1)
    Do $$$AssertEquals(dev.name, "%Developer")
    Do $$$AssertEquals(dev.resources.%Get(0).name, "%DB_USER")
    Do $$$AssertEquals(dev.resources.%Get(0).permissions, "RW")
    Set rules = ..Rules(report)
    Do $$$AssertTrue(rules [ "PUBLIC_WRITE_OR_USE_SENSITIVE:%DB_OPEN,", rules)
    Do $$$AssertTrue(rules [ "PUBLIC_WRITE_OR_USE_SENSITIVE:%Admin_Manage,", rules)
    Do $$$AssertTrue(rules [ "PUBLIC_WRITE_OR_USE:%Service_Open,", rules)
    Do $$$AssertNotTrue(rules [ "%DB_IRISLIB", "public read alone is not a finding")
    Do $$$AssertTrue(rules [ "ROLE_GRANTS_ALL:Shadow,", rules)
    Do $$$AssertNotTrue(rules [ "ROLE_GRANTS_ALL:%All,")
    Do $$$AssertEquals(report.summary.high, 3)
    Do $$$AssertEquals(report.summary.medium, 1)
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak")
}

Method TestFailOnFindingsKeepsTheReport()
{
    Do ..ScriptInstance()
    Set sc = ..Build({"failOnFindings": true}, .report)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "3 high findings: ")
    Do $$$AssertEquals(report.details.resources.%Size(), 5)
}

Method TestRefusals()
{
    Do ..ScriptInstance()
    Do ..Script("role?name=Shadow", "ERROR #822: Access Denied", 403)
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertTrue(..Rules(report) [ "INCOMPLETE_READ:role Shadow,")

    Do ..Script("roles", "ERROR #822: Access Denied", 403)
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertTrue(..Rules(report) [ "INCOMPLETE_READ:roles,")
    Do $$$AssertEquals(report.details.resources.%Size(), 5)

    Do ..Script("resources", "ERROR #822: Access Denied", 403)
    Set sc = ..Build(, .report)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "returned HTTP 403: ERROR #822: Access Denied")
}

Method TestCapAt200Roles()
{
    Set list = []
    For i = 1:1:201 { Do list.%Push({"Name": ("r"_i)}) }
    Do ..Script("roles", list)
    Do ..Script("resources", [])
    Do ..Build(, .report)
    Do $$$AssertEquals(report.details.roles.%Size(), 200)
    Do $$$AssertTrue(..Rules(report) [ "NOT_ALL_READ:roles,")
}

}
