/// Spec 005 T005/T012: the shipped declared step types, run through the executor's frame.
Class sentai.unittest.steps.ShippedStepsTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod ModelRowCounts() As %String
{
    Set counts = ""
    For table = "Flow", "Step", "Edge", "Run", "StepRun" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS c FROM sentai_model."_table)
        Do rs.%Next()
        Set counts = counts_table_"="_rs.%Get("c")_" "
    }
    Quit counts
}

Method TestDatabaseSizeReportListsDatabases()
{
    Set before = ..ModelRowCounts()
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(##class(sentai.steps.DatabaseSizeReport).%New(), .outcome)
    Do $$$AssertEquals(outcome("ok"), 1, outcome("reason"))
    Set result = {}.%FromJSON(outcome("result"))
    Do $$$AssertTrue(result.databases.%Size() > 0)
    Set found = 0
    Set iter = result.databases.%GetIterator()
    While iter.%GetNext(.k, .db) {
        If (db.name = "IRISAPP_DATA") {
            Set found = 1
            Do $$$AssertTrue(db.directory '= "")
            Do $$$AssertEquals(db.%GetTypeOf("sizeMB"), "number")
            Do $$$AssertEquals(db.%GetTypeOf("freeMB"), "number")
            Do $$$AssertTrue(db.sizeMB > 0)
        }
    }
    Do $$$AssertTrue(found, "IRISAPP_DATA listed")
    Do $$$AssertEquals(..ModelRowCounts(), before, "read-only: nothing written")
}

/// T012 (FR-008a, SC-005): with no threshold every location passes.
Method TestHeadroomLaxThresholdPasses()
{
    Set task = ##class(sentai.steps.StorageHeadroomCheck).%New()
    Set task.MinFreePercent = 0
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(task, .outcome)
    Do $$$AssertEquals(outcome("ok"), 1, outcome("reason"))
    Set result = ##class(%DynamicObject).%FromJSON(outcome("result"))
    Do $$$AssertEquals(result.minFreePercent, 0)
    Do $$$AssertTrue(result.locations.%Size() > 0)
    Set journal = ##class(%SYS.Journal.System).GetPrimaryDirectory(), sawJournal = 0
    Set iter = result.locations.%GetIterator()
    While iter.%GetNext(.k, .loc) {
        Do $$$AssertEquals(loc.ok, 1, loc.path)
        Do $$$AssertEquals(loc.%GetTypeOf("freePercent"), "number", loc.path)
        Set:(loc.path = journal) sawJournal = 1
    }
    Do $$$AssertTrue(sawJournal, "the journal directory is checked")
}

/// T012: an impossible threshold fails, naming each location and its free percentage.
Method TestHeadroomForcedThresholdFailsNamingLocations()
{
    Set task = ##class(sentai.steps.StorageHeadroomCheck).%New()
    Set task.MinFreePercent = 99.99
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(task, .outcome)
    Do $$$AssertEquals(outcome("ok"), 0)
    Set journal = ##class(%SYS.Journal.System).GetPrimaryDirectory()
    Do $$$AssertTrue(outcome("reason") [ journal, outcome("reason"))
    Do $$$AssertTrue(outcome("reason") [ "99.99", "names the threshold")
    Set result = ##class(%DynamicObject).%FromJSON(outcome("result"))
    Do $$$AssertTrue(result.locations.%Size() > 0, "the report is kept on failure")
}

/// T012 / R-3: an unreadable path is an error string from Python, never an exception.
Method TestDiskFreeReportsAnErrorAsText()
{
    Set answer = ##class(sentai.steps.StorageHeadroomCheck).DiskFree("/nonexistent/dir/")
    Do $$$AssertEquals($P(answer, " "), "error", answer)
    Do $$$AssertTrue(answer [ "FileNotFoundError", answer)
    Set answer = ##class(sentai.steps.StorageHeadroomCheck).DiskFree(##class(%SYS.Journal.System).GetPrimaryDirectory())
    Do $$$AssertEquals($P(answer, " "), "ok", answer)
}

}
