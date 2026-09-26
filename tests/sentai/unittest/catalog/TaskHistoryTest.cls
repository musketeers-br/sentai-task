/// Spec 006 T006 — recent runs from the proven history read (research R-4): execution rows only
/// (`Routine` = the task's class; admin events carry `TASKMGR`), at most 5, verbatim, item read
/// only, with no computed duration.
Class sentai.unittest.catalog.TaskHistoryTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Row(n As %Integer, routine As %String, status As %String = "1", result As %String = "Success") As %DynamicObject
{
    Set row = {"LastStart": ("2026-09-2"_n_" 00:00:00"), "Completed": ("2026-09-2"_n_" 00:00:00"), "Status": (status), "Result": (result), "Namespace": "%SYS", "Routine": (routine), "Pid": "1", "ErrDate": "", "Name": "Switch Journal", "Username": "_SYSTEM", "LogDatetime": ("2026-09-2"_n_" 00:00:01")}
    Do row.%Set("TaskId", 1, "number")
    Do row.%Set("ErrNumber", 0, "number")
    Quit row
}

ClassMethod ScriptHistory(rows As %DynamicArray, httpStatus As %Integer = 200)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task/history?taskId=1", "GET", httpStatus, "", ##class(sentai.unittest.catalog.CatalogFixtures).Envelope(rows))
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(1, "Switch Journal", "%SYS.Task.SwitchJournal")
}

Method TestOnlyExecutionRowsVerbatimNewestFirst()
{
    Set rows = []
    For n = 9:-1:3 {
        Do rows.%Push(..Row(n, $S(n # 2:"%SYS.Task.SwitchJournal", 1:"TASKMGR"), $S(n = 5:"ERROR #5001: boom", 1:"1"), $S(n = 5:"", 1:"Success")))
    }
    Do ..ScriptHistory(rows)
    Set runs = ##class(sentai.catalog.TaskService).Read(1, "fake-token").body.recentRuns
    Do $$$AssertEquals(runs.%Size(), 4, "rows 9, 7, 5, 3")
    Do $$$AssertEquals(runs.%Get(0).LastStart, "2026-09-29 00:00:00")
    Do $$$AssertEquals(runs.%Get(2).Status, "ERROR #5001: boom")
    Set row = runs.%Get(0), keys = ""
    Set iter = row.%GetIterator()
    While iter.%GetNext(.k, .v) { Set keys = keys_$S(keys = "":"", 1:",")_k }
    Do $$$AssertEquals(keys, "LastStart,Completed,Status,Result,Username,LogDatetime", "platform keys only, no duration")
}

Method TestAtMostFive()
{
    Set rows = []
    For n = 9:-1:2 { Do rows.%Push(..Row(n, "%SYS.Task.SwitchJournal")) }
    Do ..ScriptHistory(rows)
    Set runs = ##class(sentai.catalog.TaskService).Read(1, "fake-token").body.recentRuns
    Do $$$AssertEquals(runs.%Size(), 5)
    Do $$$AssertEquals(runs.%Get(4).LastStart, "2026-09-25 00:00:00")
}

Method TestOnlyAdminEventsGiveAnEmptyList()
{
    Do ..ScriptHistory([(..Row(9, "TASKMGR", "1", "Suspended task")), (..Row(8, "TASKMGR", "1", "Create Switch Journal"))])
    Set task = ##class(sentai.catalog.TaskService).Read(1, "fake-token").body
    Do $$$AssertEquals(task.recentRuns.%ToJSON(), "[]")
    Do $$$AssertNotTrue(task.%IsDefined("unavailable"))
}

Method TestRefusedHistoryOrUnknownClassIsFlaggedNotEmpty()
{
    Do ..ScriptHistory([], 403)
    Set task = ##class(sentai.catalog.TaskService).Read(1, "fake-token").body
    Do $$$AssertNotTrue(task.%IsDefined("recentRuns"), "absent, not an empty list pretending")
    Set u = task.unavailable.%Get(0)
    Do $$$AssertEquals(u.read, "history")
    Do $$$AssertEquals(u.fields.%ToJSON(), "[""recentRuns""]")
    Do $$$AssertEquals(u.httpStatus, 403)
    Do $$$AssertEquals(u.platformStatus.%ToJSON(), "{""errors"":[],""summary"":""""}")

    // Without the class, executions cannot be told from admin events: flagged with the single read.
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(404)
    Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult())
    Set shaped = ##class(sentai.catalog.TaskShape).Build(1, ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(1, "Switch Journal"), single, info)
    Do ##class(sentai.catalog.TaskShape).AttachRecentRuns(shaped, ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, [(..Row(9, "%SYS.Task.SwitchJournal"))]), single)
    Do $$$AssertNotTrue(shaped.%IsDefined("recentRuns"))
    Set last = shaped.unavailable.%Get(shaped.unavailable.%Size() - 1)
    Do $$$AssertEquals(last.read, "history")
    Do $$$AssertEquals(last.httpStatus, 404)
}

Method TestListNeverReadsHistory()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([(##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(1, "Switch Journal"))])
    Do ..ScriptHistory([(..Row(9, "%SYS.Task.SwitchJournal"))])
    Set item = ##class(sentai.catalog.TaskService).List("fake-token").body.items.%Get(0)
    Do $$$AssertNotTrue(item.%IsDefined("recentRuns"))
    Do $$$AssertEquals($D(^sentaiTestDouble("gets", "/api/admin/v2/task/history?taskId=1")), 0)
}

}
