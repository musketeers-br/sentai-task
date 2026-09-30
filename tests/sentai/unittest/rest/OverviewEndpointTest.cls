/// Spec 018 T007/T014/T020/T025: the overview routes' status codes and refusals.
Class sentai.unittest.rest.OverviewEndpointTest Extends sentai.unittest.SentaiTestCase
{

Property FlowIdBefore As %Integer [ InitialExpression = 0 ];

Method OnBeforeOneTest() As %Status
{
    Set max = 0
    &sql(SELECT MAX(%ID) INTO :max FROM sentai_model.Flow)
    Set ..FlowIdBefore = +$G(max)
    Quit ##super()
}

Method OnAfterOneTest() As %Status
{
    Set floor = ..FlowIdBefore
    &sql(DELETE FROM sentai_model.Edge WHERE flow > :floor)
    &sql(DELETE FROM sentai_model."Join" WHERE flow > :floor)
    &sql(DELETE FROM sentai_model.Step WHERE flow > :floor)
    &sql(DELETE FROM sentai_model.Flow WHERE %ID > :floor)
    Quit ##super()
}

Method NewRequest(body As %DynamicObject = "", target As %String = "")
{
    Set %request = ##class(%CSP.Request).%New()
    Set:(target '= "") %request.Data("target", 1) = target
    If $IsObject(body) {
        Set %request.Content = ##class(%Stream.TmpCharacter).%New()
        Do %request.Content.Write(body.%ToJSON())
    }
    Set %response = ##class(%CSP.Response).%New()
}

Method TestReadingRoutes()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ..NewRequest()
    Do ##class(sentai.rest.Dispatcher).ReadOverviewReading("processes")
    Do $$$AssertEquals(%response.Status, 200)
    Do ##class(sentai.unittest.AdminApiDouble).Reset(), ##class(sentai.unittest.AdminApiDouble).Enable()
    For area = "security", "nope", "..%2Fapi%2Fadmin%2Finfo" {
        Do ..NewRequest()
        Do ##class(sentai.rest.Dispatcher).ReadOverviewReading(area)
        Do $$$AssertEquals(%response.Status, 404, area)
    }
    Do ..NewRequest("", "iris-target")
    Do ##class(sentai.rest.Dispatcher).ReadOverviewReading("processes")
    Do $$$AssertEquals(%response.Status, 400)
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).HitPaths(), "")
}

Method TestSummaryRoute()
{
    For p = "processes", "locks", "devices" { Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/"_p) }
    Do ..NewRequest()
    Do ##class(sentai.rest.Dispatcher).ReadOverview()
    Do $$$AssertEquals(%response.Status, 200, "a refused area never fails the summary")
    Do ..NewRequest("", "x")
    Do ##class(sentai.rest.Dispatcher).ReadOverview()
    Do $$$AssertEquals(%response.Status, 400)
}

Method TestReportRoute()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ..NewRequest({})
    Do ##class(sentai.rest.Dispatcher).RunOverviewReport("web-app-inventory")
    Do $$$AssertEquals(%response.Status, 200)
    Do ..NewRequest({})
    Do ##class(sentai.rest.Dispatcher).RunOverviewReport("integrity-check")
    Do $$$AssertEquals(%response.Status, 422)
    Do ..NewRequest({})
    Do ##class(sentai.rest.Dispatcher).RunOverviewReport("nope")
    Do $$$AssertEquals(%response.Status, 404)
    Do ..NewRequest({"parameters": {"maxSeriousAlerts": -1}})
    Do ##class(sentai.rest.Dispatcher).RunOverviewReport("system-alerts-check")
    Do $$$AssertEquals(%response.Status, 422)
    Do ..NewRequest({"target": "iris-target"})
    Do ##class(sentai.rest.Dispatcher).RunOverviewReport("web-app-inventory")
    Do $$$AssertEquals(%response.Status, 400)
}

Method TestAreaFlowRoute()
{
    Do ..NewRequest({})
    Do ##class(sentai.rest.Dispatcher).CreateOverviewFlow("secrets")
    Do $$$AssertEquals(%response.Status, 201)
    Do ..NewRequest({})
    Do ##class(sentai.rest.Dispatcher).CreateOverviewFlow("processes")
    Do $$$AssertEquals(%response.Status, 409)
    Do ..NewRequest({"target": "x"})
    Do ##class(sentai.rest.Dispatcher).CreateOverviewFlow("secrets")
    Do $$$AssertEquals(%response.Status, 400)
}

Method TestProcessActionRoutes()
{
    Do ..NewRequest({})
    Do ##class(sentai.rest.Dispatcher).ActOnProcess("4100", "terminate")
    Do $$$AssertEquals(%response.Status, 428)
    Do ..NewRequest({"confirmation": "4100", "target": "x"})
    Do ##class(sentai.rest.Dispatcher).ActOnProcess("4100", "terminate")
    Do $$$AssertEquals(%response.Status, 400)
    Do ..NewRequest()
    Do ##class(sentai.rest.Dispatcher).ListProcessActions()
    Do $$$AssertEquals(%response.Status, 200)
    Do $$$AssertNotTrue($D(^sentaiTestDouble("postlog")), "no platform call")
}

}
