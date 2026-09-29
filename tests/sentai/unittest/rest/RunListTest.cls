/// Spec 012 US2 (contracts/api-delta.md): the paged run list — filters, stable cursor, summary
/// fields, step counts over the latest attempt, and the platform's refusal.
Class sentai.unittest.rest.RunListTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Page(flowId As %String = "", state As %String = "", limit As %Integer = 50, before As %String = "") As %DynamicArray
{
    Set out = ##class(sentai.rest.Dispatcher).RunPage(flowId, state, limit, before)
    Quit $S(out.httpStatus = 200:out.body, 1:[])
}

Method TestSummaryFieldsAndNewestFirst()
{
    Set id = ..CreateCanonicalFlow("RunListFields")
    Set r1 = ..DispatchUngated(id), r2 = ..DispatchUngated(id)
    Set page = ..Page(id)
    Do $$$AssertEquals(page.%Size(), 2)
    Set first = page.%Get(0)
    Do $$$AssertEquals(first.guid, r2.guid, "newest first")
    Do $$$AssertEquals(first.seq, +r2.%Id())
    Do $$$AssertEquals(first.flowName, ##class(sentai.model.Flow).%OpenId(id, 0).name)
    Do $$$AssertTrue(first.%IsDefined("totalDurationMs"))
    Do $$$AssertEquals(first.stepCounts.queued, 5)
    Do $$$AssertEquals(first.stepCounts.completed, 0)
}

Method TestFlowAndStateFilters()
{
    Set a = ..CreateCanonicalFlow("RunListA"), b = ..CreateCanonicalFlow("RunListB")
    Set ra = ..DispatchUngated(a), rb = ..DispatchUngated(b)
    Set rb.state = "failed"
    Do rb.%Save()
    Do $$$AssertEquals(..Page(a).%Size(), 1)
    Do $$$AssertEquals(..Page(b, "failed").%Size(), 1)
    Do $$$AssertEquals(..Page(b, "completed").%Size(), 0)
}

/// FR-008: paging by cursor never repeats a run, even when newer runs arrive between pages.
Method TestCursorIsStableWhenRunsArrive()
{
    Set id = ..CreateCanonicalFlow("RunListCursor")
    For i = 1:1:5 { Do ..DispatchUngated(id) }
    Set page1 = ..Page(id, "", 2)
    Do $$$AssertEquals(page1.%Size(), 2)
    Do ..DispatchUngated(id)
    Set page2 = ..Page(id, "", 2, page1.%Get(1).seq)
    Do $$$AssertEquals(page2.%Size(), 2)
    Do $$$AssertTrue(page2.%Get(0).seq < page1.%Get(1).seq, "the next page continues after the last seen run")
    Set seen = page1.%Get(0).seq_","_page1.%Get(1).seq
    Do $$$AssertNotTrue((","_seen_",") [ (","_page2.%Get(0).seq_","), "no repeat")
}

/// Counts use the latest attempt: a re-run of a failed step counts once, as queued.
Method TestCountsUseTheLatestAttempt()
{
    Set id = ..CreateCanonicalFlow("RunListRerun")
    Set run = ..DispatchUngated(id)
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do sr.TransitionTo("running")
    Do sr.TransitionTo("failed", "x")
    $$$ThrowOnError(##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, sr.guid, .newGuid))
    Set counts = ..Page(id).%Get(0).stepCounts
    Do $$$AssertEquals(counts.failed, 0)
    Do $$$AssertEquals(counts.queued, 5)
}

/// The flow's current name is shown after a rename.
Method TestFlowNameIsCurrent()
{
    Set id = ..CreateCanonicalFlow("RunListRename")
    Do ..DispatchUngated(id)
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 4)
    Set flow.name = flow.name_" renamed"
    Do flow.%Save()
    Do $$$AssertEquals(..Page(id).%Get(0).flowName, flow.name)
}

/// The HTTP layer's parameter checks (D-6).
Method TestParameterChecks()
{
    For case = "0|LIMIT_OUT_OF_RANGE", "201|LIMIT_OUT_OF_RANGE", "abc|LIMIT_OUT_OF_RANGE" {
        Do ..AssertListRefused($P(case, "|"), "", "", $P(case, "|", 2))
    }
    Do ..AssertListRefused("", "bogus", "", "STATE_UNKNOWN")
    Do ..AssertListRefused("", "", "x", "CURSOR_INVALID")
}

Method AssertListRefused(limit As %String, state As %String, before As %String, code As %String)
{
    Set %request = ##class(%CSP.Request).%New()
    Set:(limit '= "") %request.Data("limit", 1) = limit
    Set:(state '= "") %request.Data("state", 1) = state
    Set:(before '= "") %request.Data("before", 1) = before
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ListRuns()
    Do $$$AssertEquals(%response.Status, 400, code)
}

/// Spec 015 T020: every item says how it started; the list filters by it (older runs are manual).
Method TestTriggerFieldAndFilter()
{
    Set id = ..CreateCanonicalFlow("RunListTrigger")
    Set manual = ..DispatchUngated(id), scheduled = ..DispatchUngated(id)
    Set scheduled.trigger = "scheduled"
    Do scheduled.%Save()
    Set legacy = ..DispatchUngated(id)
    Set legacy.trigger = ""
    Do legacy.%Save()
    Set page = ..Page(id)
    Do $$$AssertEquals(page.%Get(1).trigger, "scheduled")
    Do $$$AssertEquals(page.%Get(0).trigger, "manual", "no trigger recorded reads as manual")
    Set only = ##class(sentai.rest.Dispatcher).RunPage(id, "", 50, "", "scheduled").body
    Do $$$AssertEquals(only.%Size(), 1)
    Do $$$AssertEquals(only.%Get(0).guid, scheduled.guid)
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).RunPage(id, "", 50, "", "manual").body.%Size(), 2)
}

}
