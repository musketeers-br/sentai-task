Class sentai.unittest.rest.CatalogTasksTest Extends sentai.unittest.SentaiTestCase
{

Method TestNonProductTasksAppearAndAreFilterable()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "",
        "{""result"":[{""Id"":1,""Name"":""Switch Journal"",""Type"":""System"",""Namespace"":""%SYS"",""Suspended"":false,""LastFinished"":"""",""NextScheduled"":""2026-09-22 00:00:00""}]}")

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ListCatalogTasks()
    Do $$$AssertEquals(%response.Status, 200)

    Set out = ##class(sentai.catalog.TaskService).List("fake-token")
    Do $$$AssertEquals(out.total, 1)
    Do $$$AssertEquals(out.matched, 1)
}

Method TestSuspendTogglesStateReflectedOnNextRead()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks/1/suspend", "POST", 200, "", "{}")
    Set sc = ##class(sentai.catalog.TaskService).Suspend(1, 1, "fake-token")
    Do $$$AssertStatusOK(sc)
}

}
