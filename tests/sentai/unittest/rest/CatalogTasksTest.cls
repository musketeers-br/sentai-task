Class sentai.unittest.rest.CatalogTasksTest Extends sentai.unittest.SentaiTestCase
{

Method TestNonProductTasksAppearAndAreFilterable()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "",
        "{""result"":[{""Id"":1,""Name"":""Switch Journal"",""Type"":""System"",""Namespace"":""%SYS"",""Suspended"":false,""LastFinished"":"""",""NextScheduled"":""2026-09-22 00:00:00""}]}")
    // Spec 006: each listed task is also read per task (single + info) — the list alone carries
    // no class, run-as user or status (research R-1).
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(1, "Switch Journal", "%SYS.Task.SwitchJournal")

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ListCatalogTasks()
    Do $$$AssertEquals(%response.Status, 200)

    Set out = ##class(sentai.catalog.TaskService).List("fake-token").body
    Do $$$AssertEquals(out.total, 1)
    Do $$$AssertEquals(out.matched, 1)
}

Method TestSuspendTogglesStateReflectedOnNextRead()
{
    // Spec 006 R-3: the platform's proven contract (the old /v2/tasks/<id>/suspend path is 404),
    // confirmed by a re-read of the task.
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/suspend", "POST", 200, "", "{}")
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(1, "Switch Journal", "%SYS.Task.SwitchJournal", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1))
    Set out = ##class(sentai.catalog.TaskService).SetSuspended(1, 1, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertTrue(out.body.suspended)
}

}
