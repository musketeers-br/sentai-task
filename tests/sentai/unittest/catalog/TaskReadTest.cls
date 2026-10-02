/// Spec 006 T001 — the corrected read: every value comes from the platform's own reads (list for
/// which tasks exist, single for class/run-as/period, info for status/times/suspended), failed
/// per-task reads are visible, and refusals are verbatim (research R-1, R-5; data-model.md).
Class sentai.unittest.catalog.TaskReadTest Extends sentai.unittest.SentaiTestCase
{

// --- Mapping (pure, no double) ---

Method TestBuildMapsEveryFieldFromItsRead()
{
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, {"Name": "Integrity Check", "NameSpace": "%SYS", "TaskClass": "%SYS.Task.IntegrityCheck", "RunAsUser": "_SYSTEM", "TimePeriod": "Weekly"})
    Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1, "1", "", "2026-09-26 00:00:01", "2026-09-26 00:00:02", "2026-09-28 02:00:00"))
    Set entry = ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(4, "Integrity Check", "%SYS", 0)
    Set t = ##class(sentai.catalog.TaskShape).Build(4, entry, single, info)

    Do $$$AssertEquals(t.taskId, 4)
    Do $$$AssertEquals(t.name, "Integrity Check")
    Do $$$AssertEquals(t.namespace, "%SYS")
    Do $$$AssertEquals(t.class, "%SYS.Task.IntegrityCheck")
    Do $$$AssertEquals(t.runAsUser, "_SYSTEM")
    Do $$$AssertEquals(t.timePeriod, "Weekly")
    Do $$$AssertEquals(t.nextRun, "2026-09-28 02:00:00")
    Do $$$AssertEquals(t.lastStarted, "2026-09-26 00:00:01")
    Do $$$AssertEquals(t.lastFinished, "2026-09-26 00:00:02")
    Do $$$AssertEquals(t.lastRun, "2026-09-26 00:00:02")
    Do $$$AssertEquals(t.status, "1")
    Do $$$AssertEquals(t.lastError, "")
    Do $$$AssertEquals(t.%GetTypeOf("suspended"), "boolean")
    Do $$$AssertTrue(t.suspended)
    Do $$$AssertEquals(t.%GetTypeOf("isDestructive"), "boolean")
    Do $$$AssertEquals(t.isDestructive, t.destructive)
    Do $$$AssertNotTrue(t.%IsDefined("state"))
    Do $$$AssertNotTrue(t.%IsDefined("className"))
    Do $$$AssertNotTrue(t.%IsDefined("unavailable"))
    Do $$$AssertNotTrue(t.%IsDefined("recentRuns"))
}

Method TestStatusIsThePlatformsOwnText()
{
    Do $$$AssertEquals(##class(sentai.catalog.TaskShape).StatusText("1"), "1")
    Set serialized = $$$ERROR($$$GeneralError, "x")
    // Round-trip through JSON, as the platform delivers it (research R-5: byte-identical).
    Set carried = {}.%FromJSON({"s": (serialized)}.%ToJSON()).s
    Do $$$AssertEquals(##class(sentai.catalog.TaskShape).StatusText(carried), "ERROR #5001: x")
    Do $$$AssertEquals(##class(sentai.catalog.TaskShape).StatusText("anything else"), "anything else")
    Do $$$AssertEquals(##class(sentai.catalog.TaskShape).StatusText(""), "")
}

Method TestLastErrorIsVerbatim()
{
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, {"TaskClass": "x", "RunAsUser": "u", "TimePeriod": "Daily"})
    For error = "Success", "" {
        Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(0, "1", error))
        Set t = ##class(sentai.catalog.TaskShape).Build(7, ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(7, "Purge"), single, info)
        Do $$$AssertEquals(t.lastError, error)
    }
}

Method TestFailedSingleReadIsFlaggedNotFilled()
{
    Set notFound = {}.%FromJSON(##class(sentai.unittest.catalog.CatalogFixtures).NotFoundJSON(1003))
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(404, "", notFound.status.errors)
    Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult())
    Set t = ##class(sentai.catalog.TaskShape).Build(1003, ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(1003, "Gone"), single, info)

    For field = "class", "runAsUser", "timePeriod" { Do $$$AssertNotTrue(t.%IsDefined(field), field_" absent") }
    Do $$$AssertEquals(t.unavailable.%Size(), 1)
    Set u = t.unavailable.%Get(0)
    Do $$$AssertEquals(u.read, "single")
    Do $$$AssertEquals(u.fields.%ToJSON(), "[""class"",""runAsUser"",""timePeriod""]")
    Do $$$AssertEquals(u.httpStatus, 404)
    Do $$$AssertEquals(u.platformStatus.errors.%Get(0).error, "ERROR #5809: Object to Load not found, class '%SYS.Task', ID '1003'")
    Do $$$AssertTrue(t.destructiveUnknown)
}

Method TestFailedInfoReadIsFlaggedWithTheEmpty403Status()
{
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, {"TaskClass": "x", "RunAsUser": "u", "TimePeriod": "Daily"})
    Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(403)
    Set t = ##class(sentai.catalog.TaskShape).Build(5, ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(5, "Security Scan"), single, info)

    For field = "nextRun", "lastStarted", "lastFinished", "status", "lastError", "suspended", "lastRun" {
        Do $$$AssertNotTrue(t.%IsDefined(field), field_" absent")
    }
    Set u = t.unavailable.%Get(0)
    Do $$$AssertEquals(u.read, "info")
    Do $$$AssertEquals(u.fields.%ToJSON(), "[""nextRun"",""lastStarted"",""lastFinished"",""status"",""lastError"",""suspended""]")
    Do $$$AssertEquals(u.platformStatus.%ToJSON(), "{""errors"":[],""summary"":""""}")
}

/// Spec 023 T022 (research R-3): the platform's own Description, verbatim; absent when it is
/// empty or the single read failed — never filled in.
Method TestDescriptionIsTheSingleReadsOwnTextOrAbsent()
{
    Set entry = ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(8, "Inventory Scan")
    Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult())
    Set text = "Run a scan of the system inventory on install or upgrade and on demand thereafter"
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, {"TaskClass": "%SYS.Task.InventoryScan", "Description": (text)})
    Do $$$AssertEquals(##class(sentai.catalog.TaskShape).Build(8, entry, single, info).description, text)

    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, {"TaskClass": "%SYS.Task.InventoryScan", "Description": ""})
    Do $$$AssertNotTrue(##class(sentai.catalog.TaskShape).Build(8, entry, single, info).%IsDefined("description"), "empty")

    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(403)
    Do $$$AssertNotTrue(##class(sentai.catalog.TaskShape).Build(8, entry, single, info).%IsDefined("description"), "single refused")
}

// --- Service and REST, using the double ---

/// Spec 023 T022 (research R-2): counts over every task the list read enumerated, before any
/// filter — so they do not change when a filter does. A task whose info read failed has no
/// suspended value and is counted in no suspended total.
Method TestCountsCoverEveryTaskAndIgnoreFilters()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([(##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(4, "Integrity Check")), (##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(5, "Purge Tasks")), (##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(6, "Inventory Scan")), (##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(7, "Unread"))])
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(4, "Integrity Check", "%SYS.Task.IntegrityCheck", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1))
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(5, "Purge Tasks", "%SYS.Task.PurgeTaskHistory")
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(6, "Inventory Scan", "%SYS.Task.InventoryScan", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1))
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptSingle(7, "%SYS.Task.IntegrityCheck", "_SYSTEM", "Weekly", "Unread")
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/info?id=7", "GET", 403, "", ##class(sentai.unittest.catalog.CatalogFixtures).Envelope({}))

    For args = $LB("all", "0", "0"), $LB("suspended", "0", "0"), $LB("all", "0", "1"), $LB("all", "1", "0") {
        Set out = ##class(sentai.catalog.TaskService).List("fake-token", "", "", $LG(args, 1), $LG(args, 2), $LG(args, 3))
        Do $$$AssertEquals(out.httpStatus, 200, $LTS(args))
        Do $$$AssertEquals(out.body.total, 4, $LTS(args))
        Do $$$AssertEquals(out.body.counts.%ToJSON(), "{""suspended"":2,""destructive"":1,""unclassified"":1}", $LTS(args))
        Do $$$AssertEquals(out.body.counts.%GetTypeOf("suspended"), "number")
    }
    Set out = ##class(sentai.catalog.TaskService).List("fake-token", "", "", "all", "0", "1")
    Do $$$AssertEquals(out.body.matched, 1)
    Do $$$AssertEquals(out.body.items.%Get(0).name, "Inventory Scan")
}

/// Spec 023 T022: description reaches both the list and the item read.
Method TestDescriptionReachesListAndItem()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([(##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(8, "Inventory Scan"))])
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptSingle(8, "%SYS.Task.InventoryScan", "_SYSTEM", "On Demand", "Inventory Scan", "%SYS", "Scan the inventory")
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptInfo(8, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult())
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/history?taskId=8", "GET", 200, "", ##class(sentai.unittest.catalog.CatalogFixtures).Envelope([]))
    Do $$$AssertEquals(##class(sentai.catalog.TaskService).List("fake-token").body.items.%Get(0).description, "Scan the inventory")
    Do $$$AssertEquals(##class(sentai.catalog.TaskService).Read(8, "fake-token").body.description, "Scan the inventory")
}

Method TestSuspendedComesFromInfoNotFromTheLossyList()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([(##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(4, "Integrity Check", "%SYS", 0))])
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(4, "Integrity Check", "%SYS.Task.IntegrityCheck", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1))
    Set out = ##class(sentai.catalog.TaskService).List("fake-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Set t = out.body.items.%Get(0)
    Do $$$AssertTrue(t.suspended, "list says false, info says true: info wins (R-1)")
    Do $$$AssertEquals(t.class, "%SYS.Task.IntegrityCheck")
}

Method TestListRefusalIsTheWholeCallVerbatim()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([], 403)
    Set out = ##class(sentai.catalog.TaskService).List("fake-token")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.status, 403)
    Do $$$AssertEquals(out.problem.detail, "")
    Do $$$AssertEquals(out.problem.platformStatus.%ToJSON(), "{""errors"":[],""summary"":""""}")
    Do $$$AssertNotTrue(out.%IsDefined("body"))
}

Method TestItemReadEqualsTheListItem()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([(##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(4, "Integrity Check"))])
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(4, "Integrity Check", "%SYS.Task.IntegrityCheck", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1, "1", "", "", "", "2026-09-28 02:00:00"))
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/history?taskId=4", "GET", 200, "", ##class(sentai.unittest.catalog.CatalogFixtures).Envelope([]))
    Set listed = ##class(sentai.catalog.TaskService).List("fake-token").body.items.%Get(0)
    Set read = ##class(sentai.catalog.TaskService).Read(4, "fake-token")
    Do $$$AssertEquals(read.httpStatus, 200)
    Set item = read.body
    If item.%IsDefined("recentRuns") Do item.%Remove("recentRuns")
    Do $$$AssertEquals(item.%ToJSON(), listed.%ToJSON())
}

Method TestItemReadNotFoundIsVerbatim()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task?id=99999", "GET", 404, "", ##class(sentai.unittest.catalog.CatalogFixtures).NotFoundJSON(99999))
    Set out = ##class(sentai.catalog.TaskService).Read(99999, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 404)
    Do $$$AssertEquals(out.problem.detail, "ERROR #5809: Object to Load not found, class '%SYS.Task', ID '99999'")
    Do $$$AssertEquals(out.problem.platformStatus.errors.%Get(0).code, 5809)
}

Method TestNonIntegerIdIsNotFoundWithoutAPlatformCall()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    For id = "abc", "0", "-1", "1.5" {
        Do ##class(sentai.rest.Dispatcher).ReadCatalogTask(id)
        Do $$$AssertEquals(%response.Status, 404, "id "_id)
    }
    Do $$$AssertEquals($D(^sentaiTestDouble("gets")), 0, "no platform GET")
}

Method TestReadsCarryTheRequestTokenAndUnreachableIs502()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([(##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(4, "Integrity Check"))])
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(4, "Integrity Check", "%SYS.Task.IntegrityCheck")
    Do ##class(sentai.catalog.TaskService).List("fake-token")
    Set url = ""
    For {
        Set url = $ORDER(^sentaiTestDouble("gets", url))
        Quit:url=""
        Do $$$AssertEquals(^sentaiTestDouble("gets", url), "fake-token", url)
    }
    Do $$$AssertTrue($D(^sentaiTestDouble("gets", "/api/admin/v2/task/info?id=4")))

    Do ##class(sentai.unittest.AdminApiDouble).Reset()
    Do ##class(sentai.unittest.AdminApiDouble).Enable()
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 0, "", "")
    Set out = ##class(sentai.catalog.TaskService).List("fake-token")
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertTrue(out.problem.detail [ "PLATFORM_UNREACHABLE")
}

}
