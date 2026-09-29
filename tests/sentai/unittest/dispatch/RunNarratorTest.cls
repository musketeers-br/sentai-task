/// Spec 012 US1 (data-model §2): the run log's message catalog, splitting of long platform text,
/// target-outage dedupe, and "a log write never throws" (FR-004).
Class sentai.unittest.dispatch.RunNarratorTest Extends sentai.unittest.SentaiTestCase
{

/// Log entries of `runId`, oldest first, as "severity|stepId|message".
ClassMethod Lines(runId As %String) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT severity, stepId, message FROM sentai_model.LogEntry WHERE run = ? ORDER BY ""at"", ID", runId)
    While rs.%Next() { Do out.%Push(rs.%Get("severity")_"|"_rs.%Get("stepId")_"|"_rs.%Get("message")) }
    Quit out
}

ClassMethod Last(runId As %String) As %String
{
    Set lines = ..Lines(runId)
    Quit $S(lines.%Size():lines.%Get(lines.%Size() - 1), 1:"")
}

Method TestDispatchedIsTheFirstEntry()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrDispatch"))
    Set first = ..Lines(run.%Id()).%Get(0)
    Do $$$AssertEquals(first, "info||Run dispatched by tester (flow revision 1, 5 steps)")
}

Method TestStepCatalog()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrSteps"))
    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Do sr.TransitionTo("running")
    Do $$$AssertEquals(..Last(run.%Id()), "info|01|#01 IC USER started on local")
    Do sr.TransitionTo("completed")
    Do $$$AssertTrue(..Last(run.%Id()) ? 1"info|01|#01 completed in "2N1":"2N, ..Last(run.%Id()))

    Set sr2 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "02", 4)
    Do sr2.TransitionTo("running")
    Do sr2.TransitionTo("failed", "ERROR #5002: the platform's own words")
    Do $$$AssertTrue(..Last(run.%Id()) ? 1"error|02|#02 failed after "2N1":"2N1": ""ERROR #5002: the platform's own words""", ..Last(run.%Id()))

    Set sr3 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "03", 4)
    Do sr3.TransitionTo("cancelled")
    Do $$$AssertEquals(..Last(run.%Id()), "warning|03|#03 cancelled")
}

Method TestJoinBlockedNamesTheInput()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrJoin"))
    For id = "01", "02", "03" {
        Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), id, 4)
        Do sr.TransitionTo("running")
        Do sr.TransitionTo($S(id = "02":"failed", 1:"completed"), $S(id = "02":"boom", 1:""))
    }
    Do ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)
    Set lines = ..Lines(run.%Id()), found = 0
    For i = 0:1:(lines.%Size() - 1) {
        Set:(lines.%Get(i) = "error|04|#04 not started: input #02 failed (all inputs must succeed)") found = 1
    }
    Do $$$AssertTrue(found, lines.%ToJSON())
}

Method TestLongPlatformTextIsSplitWhole()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrLong"))
    Set text = "", chunk = "0123456789"
    For i = 1:1:950 { Set text = text_chunk }
    $$$ThrowOnError(##class(sentai.dispatch.RunNarrator).Write(run.%Id(), "01", "error", text))
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT message FROM sentai_model.LogEntry WHERE run = ? AND stepId = '01' ORDER BY ""at"", ID", run.%Id())
    Set joined = "", parts = 0
    While rs.%Next() {
        Set m = rs.%Get("message"), parts = parts + 1
        Do $$$AssertTrue($L(m) <= 4000)
        Set joined = joined_$P(m, ") ", 2, *)
    }
    Do $$$AssertEquals(parts, 3)
    Do $$$AssertEquals(joined, text, "nothing lost, in order")
}

/// SC-006: three failed attempts and two answers of the same target in one run → two entries.
Method TestTargetOutageDedupe()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrOutage"))
    For i = 1:1:3 { Do ##class(sentai.dispatch.WaveDispatcher).MarkTargetFailed(run.guid, "t1", "connect refused") }
    For i = 1:1:2 { Do ##class(sentai.dispatch.WaveDispatcher).MarkTargetAnswered(run.guid, "t1") }
    Set lines = ..Lines(run.%Id()), about = 0
    For i = 0:1:(lines.%Size() - 1) { Set:(lines.%Get(i) [ "Target t1") about = about + 1 }
    Do $$$AssertEquals(about, 2, lines.%ToJSON())
    Do $$$AssertTrue(lines.%ToJSON() [ "Target t1 did not answer: \""connect refused\""; retrying every 30 s")
    Do $$$AssertTrue(lines.%ToJSON() [ "Target t1 answers again")
}

Method TestRequestedAcceptedAndRefused()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrRequest"))
    Do ##class(sentai.dispatch.RunNarrator).Requested(run.guid, "", "ana", "cancel")
    Do $$$AssertEquals(..Last(run.%Id()), "info||ana asked to cancel the run")
    Do ##class(sentai.dispatch.RunNarrator).Requested(run.guid, "02", "ana", "pause", "SentaiNotPausable: step type 'integrity-check' does not support pause in v1")
    Do $$$AssertEquals(..Last(run.%Id()), "warning|02|ana asked to pause #02; refused: ""SentaiNotPausable: step type 'integrity-check' does not support pause in v1""")
}

Method TestFinishedCountsLatestAttempts()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrFinished"))
    For id = "01", "02", "03", "04", "05" {
        Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), id, 4)
        Do sr.TransitionTo("running")
        Do sr.TransitionTo($S(id = "05":"failed", 1:"completed"), "x")
    }
    Do ##class(sentai.dispatch.WaveDispatcher).FinalizeRun(run)
    Do $$$AssertTrue(..Last(run.%Id()) ? 1"error||Run failed: 4 completed, 1 failed, 0 cancelled ("2N1":"2N1")", ..Last(run.%Id()))
}

/// FR-004: a write that cannot happen reports an error status and never throws.
Method TestNarratorNeverThrows()
{
    Set sc = ##class(sentai.dispatch.RunNarrator).Write("999999999", "01", "info", "no such run")
    Do $$$AssertTrue($$$ISERR(sc) || $$$ISOK(sc), "returned a status")
    Set sc = ##class(sentai.dispatch.RunNarrator).Requested("no-such-guid", "", "ana", "cancel")
    Do $$$AssertStatusOK(sc)
}

/// Entries written within the same second keep their order (research R-2).
Method TestSameSecondKeepsInsertionOrder()
{
    Set run = ..DispatchUngated(..CreateCanonicalFlow("NarrOrder"))
    For i = 1:1:5 { Do ##class(sentai.dispatch.RunNarrator).Write(run.%Id(), "", "info", "entry "_i) }
    Set shape = ##class(sentai.rest.Dispatcher).ShapeRun(run, 1)
    // The API is newest first.
    Do $$$AssertEquals(shape.log.%Get(0).message, "entry 5")
    Do $$$AssertEquals(shape.log.%Get(4).message, "entry 1")
}

}
