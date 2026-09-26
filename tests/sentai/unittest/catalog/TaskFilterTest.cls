/// Spec 006 T004 — filters operate on the corrected values (FR-007, data-model §Filters); values
/// that are unavailable or unknown never satisfy a filter about them.
Class sentai.unittest.catalog.TaskFilterTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Task(name As %String, class As %String = "", namespace As %String = "%SYS", suspended As %String = "", destructive As %Boolean = 0, unknown As %Boolean = 0) As %DynamicObject
{
    Set t = {"name": (name), "namespace": (namespace)}
    If (class '= "") Do t.%Set("class", class)
    If (suspended '= "") Do t.%Set("suspended", suspended, "boolean")
    Do t.%Set("destructive", destructive, "boolean")
    Do t.%Set("destructiveUnknown", unknown, "boolean")
    Quit t
}

ClassMethod M(task As %DynamicObject, q As %String = "", namespace As %String = "", filter As %String = "all", destructiveOnly As %String = "0") As %Boolean
{
    Quit ##class(sentai.catalog.TaskFilter).Matches(task, q, namespace, filter, destructiveOnly)
}

Method TestTextMatchesName()
{
    Do $$$AssertTrue(..M(..Task("Integrity Check", "%SYS.Task.IntegrityCheck"), "integrity"))
    Do $$$AssertNotTrue(..M(..Task("Switch Journal", "%SYS.Task.SwitchJournal"), "integrity"))
}

Method TestTextMatchesClassIgnoringCase()
{
    Do $$$AssertTrue(..M(..Task("Nightly", "%SYS.Task.IntegrityCheck"), "integritycheck"))
    Do $$$AssertTrue(..M(..Task("Nightly", "%SYS.Task.IntegrityCheck"), "NIGHTLY"))
}

Method TestTextWithClassUnavailableMatchesNameOnly()
{
    Do $$$AssertNotTrue(..M(..Task("Nightly"), "integrity"))
    Do $$$AssertTrue(..M(..Task("Nightly"), "night"))
}

Method TestNamespaceIgnoresCase()
{
    Do $$$AssertTrue(..M(..Task("A", "", "%SYS"), "", "%sys"))
    Do $$$AssertNotTrue(..M(..Task("A", "", "IRISAPP"), "", "%SYS"))
}

Method TestScheduledKeepsNotSuspended()
{
    Do $$$AssertTrue(..M(..Task("A", "", "%SYS", 0), "", "", "scheduled"))
    Do $$$AssertNotTrue(..M(..Task("A", "", "%SYS", 1), "", "", "scheduled"))
}

Method TestSuspendedKeepsSuspendedAndUnavailableIsExcludedFromBoth()
{
    Do $$$AssertTrue(..M(..Task("A", "", "%SYS", 1), "", "", "suspended"))
    Do $$$AssertNotTrue(..M(..Task("A", "", "%SYS", 0), "", "", "suspended"))
    Do $$$AssertNotTrue(..M(..Task("A"), "", "", "suspended"), "suspended unavailable")
    Do $$$AssertNotTrue(..M(..Task("A"), "", "", "scheduled"), "suspended unavailable")
    Do $$$AssertTrue(..M(..Task("A"), "", "", "all"))
}

Method TestDestructiveOnlyExcludesUnknown()
{
    Do $$$AssertTrue(..M(..Task("P", "", "%SYS", 0, 1, 0), "", "", "all", "1"))
    Do $$$AssertTrue(..M(..Task("P", "", "%SYS", 0, 1, 0), "", "", "all", "true"))
    Do $$$AssertNotTrue(..M(..Task("U", "", "%SYS", 0, 0, 1), "", "", "all", "1"), "unknown is not destructive-only")
    Do $$$AssertNotTrue(..M(..Task("N", "", "%SYS", 0, 0, 0), "", "", "all", "1"))
    Do $$$AssertTrue(..M(..Task("U", "", "%SYS", 0, 0, 1), "", "", "all", "false"))
}

Method TestCombinedFiltersAreAnded()
{
    Set hit = ..Task("Purge Tasks", "%SYS.Task.PurgeTaskHistory", "%SYS", 1, 1, 0)
    Do $$$AssertTrue(..M(hit, "purge", "%sys", "suspended", "1"))
    Do $$$AssertNotTrue(..M(hit, "purge", "IRISAPP", "suspended", "1"))
    Do $$$AssertNotTrue(..M(hit, "purge", "%SYS", "scheduled", "1"))
    Do $$$AssertNotTrue(..M(hit, "journal", "%SYS", "suspended", "1"))
}

Method TestValidateRefusesUnknownValues()
{
    Do $$$AssertNotTrue(##class(sentai.catalog.TaskFilter).Validate("", "", "paused", "0", .problem))
    Do $$$AssertTrue(problem [ "INVALID_FILTER: ", problem)
    Do $$$AssertNotTrue(##class(sentai.catalog.TaskFilter).Validate("", "", "all", "maybe", .problem))
    Do $$$AssertTrue(problem [ "INVALID_FILTER: ", problem)
    For filter = "all", "scheduled", "suspended" {
        For flag = "0", "1", "true", "false" {
            Do $$$AssertTrue(##class(sentai.catalog.TaskFilter).Validate("x", "%SYS", filter, flag, .problem), filter_"/"_flag)
        }
    }
}

Method TestInvalidFilterIs400WithoutAPlatformCall()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do %request.Set("filter", "paused")
    Do ##class(sentai.rest.Dispatcher).ListCatalogTasks()
    Do $$$AssertEquals(%response.Status, 400)
    Do $$$AssertEquals($D(^sentaiTestDouble("gets")), 0, "no platform GET")
    Set out = ##class(sentai.catalog.TaskService).List("fake-token", "", "", "paused")
    Do $$$AssertTrue(out.problem.detail [ "INVALID_FILTER")
}

}
