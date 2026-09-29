/// Spec 018 T013 (SC-006): no overview answer ever carries a field no allow-list names — at the
/// top level or inside nested objects — whatever the platform sends.
Class sentai.unittest.overview.OverviewSecrecyTest Extends sentai.unittest.SentaiTestCase
{

Method AssertClean(obj As %DynamicObject, what As %String)
{
    Set json = obj.%ToJSON()
    Do $$$AssertNotTrue(json [ ##class(sentai.unittest.overview.OverviewFixtures).#Leak, what_" leaks nothing")
}

Method TestEveryEntryPointIsClean()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    For area = "processes", "locks", "memory", "activity", "devices", "licenses", "web-sessions" {
        Do ..AssertClean(##class(sentai.overview.Readings).Read(area, "fake-token"), "reading "_area)
    }
    Do ..AssertClean(##class(sentai.overview.OverviewService).Summary("fake-token"), "summary")
    For area = "security", "web-apps", "alerts", "secrets" {
        Do ..AssertClean(##class(sentai.overview.AreaFlow).Definition(area, {}, "fake-token"), "flow definition "_area)
    }
}

/// Report answers carry what spec 013's allow-lists keep; a secret value never appears.
Method TestReportsNeverShowSecretValues()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/wallet/secrets?collection=SentaiTask", [{"Name": "run-as", "Type": "password", "Value": (##class(sentai.unittest.overview.OverviewFixtures).#Leak)}])
    Set out = ##class(sentai.overview.OverviewService).RunReport("secrets-inventory", {}, "fake-token")
    Do ..AssertClean(out, "secrets report")
}

}
