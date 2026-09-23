/// StartStep enqueues one eligible step on %SYSTEM.WorkMgr under its WQM category and, through
/// ExecuteStepAsync on a worker, starts the mapped administrative job (research.md R-005).
Class sentai.unittest.dispatch.StartStepTest Extends sentai.unittest.SentaiTestCase
{

Method DispatchWithCategory(category As %String) As sentai.model.Run
{
    Set payload = ..CanonicalFlowPayload("StartStep")
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        Do s.%Set("wqmCategory", category)
    }
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")
    Quit run
}

Method TestRootStepStartsOnExistingCategoryAndRecordsAdminJob()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/database-dir/integrity-check", "POST", 202, "/api/admin/v1/async-result?id=job01", "{}")
    Set run = ..DispatchWithCategory("Default")

    Set sc = ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Do $$$AssertStatusOK(sc)

    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 0)
    Do $$$AssertEquals(sr.state, "running")
    Do $$$AssertEquals(sr.adminJobId, "/api/admin/v1/async-result?id=job01")

    // The platform rejects an empty POST ("HTTP POST has no content", 400); the validated
    // request carries a JSON object body (spec 001 evidence/06-integrity-check-start.json).
    Do $$$AssertEquals($LG($G(^sentaiTestDouble("posted", "/api/admin/v2/database-dir/integrity-check")), 2), "{}")
}

Method TestUnknownCategoryFailsTheStepWithThePlatformMessage()
{
    Set run = ..DispatchWithCategory("SENTAI.DOES_NOT_EXIST")

    Set sc = ##class(sentai.dispatch.WaveDispatcher).StartStep(run, "01")
    Do $$$AssertStatusOK(sc)

    Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 0)
    Do $$$AssertEquals(sr.state, "failed")
    Do $$$AssertTrue(sr.failureReason [ "SENTAI.DOES_NOT_EXIST")
}

}
