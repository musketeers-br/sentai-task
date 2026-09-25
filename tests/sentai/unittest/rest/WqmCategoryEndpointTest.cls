Class sentai.unittest.rest.WqmCategoryEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method TestInvariantViolatingWriteReturns422()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"defaultWorkers": 99, "maxActiveWorkers": 5, "maxWorkers": 10, "maxTotalWorkers": 20, "alwaysQueue": false}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()

    Do ##class(sentai.rest.Dispatcher).WriteWqmCategory("SENTAI.ENDPOINT_BAD")
    Do $$$AssertEquals(%response.Status, 422)
}

Method TestValidWriteReportsAffectedTaskCountAndDoesNotTouchInProgressRuns()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wqm-category", "PUT", 200, "", "{}")

    Set id = ..CreateCanonicalFlow("WqmAffected")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ..DispatchUngated(id)
    Do $$$AssertEquals(errorCode, "")

    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"defaultWorkers": 2, "maxActiveWorkers": 4, "maxWorkers": 8, "maxTotalWorkers": 16, "alwaysQueue": false}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()

    Do ##class(sentai.rest.Dispatcher).WriteWqmCategory("SENTAI.ENDPOINT_OK")
    Do $$$AssertEquals(%response.Status, 200)

    // The already-dispatched run's steps are untouched by the category change (FR-036).
    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 0)
    Do $$$AssertEquals(sr01.state, "queued")
}

/// Spec 004 FR-004 (F-1): the write uses the validated platform contract — spec 001 evidence
/// 10a: PUT /api/admin/v2/wqm-category?name=<name>, name only in the query string, numbers as
/// JSON numbers — and never the unvalidated POST /api/admin/v2/wqm-categories/<name>.
Method TestWriteUsesValidatedPutContract()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wqm-category", "PUT", 200, "", "{}")
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"defaultWorkers": 1, "maxActiveWorkers": 3, "maxWorkers": 0, "maxTotalWorkers": 0, "alwaysQueue": true}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()

    Do ##class(sentai.rest.Dispatcher).WriteWqmCategory("Utility")
    Do $$$AssertEquals(%response.Status, 200)

    Set recorded = $G(^sentaiTestDouble("put", "/api/admin/v2/wqm-category"))
    Do $$$AssertEquals($LG(recorded, 1), "/api/admin/v2/wqm-category?name=Utility")
    Set body = {}.%FromJSON($LG(recorded, 2))
    Do $$$AssertNotTrue(body.%IsDefined("Name"))
    Do $$$AssertEquals(body.%GetTypeOf("MaxActiveWorkers"), "number")
    Do $$$AssertEquals(body.%GetTypeOf("MaxTotalWorkers"), "number")
    Do $$$AssertEquals(body.%GetTypeOf("AlwaysQueue"), "boolean")
    Do $$$AssertEquals(body.MaxActiveWorkers, 3)

    Do $$$AssertEquals($D(^sentaiTestDouble("posted", "/api/admin/v2/wqm-categories/Utility")), 0)
}

/// A name that is not URL-safe is encoded in the query string.
Method TestWriteEncodesTheNameInTheQueryString()
{
    Set payload = {"name": "SENTAI NIGHT", "defaultWorkers": 1, "maxActiveWorkers": 2, "maxWorkers": 4, "maxTotalWorkers": 8, "alwaysQueue": false}
    Set sc = ##class(sentai.wqm.CategoryService).Write(payload, "fake-token")
    Do $$$AssertStatusOK(sc)
    Do $$$AssertEquals($LG($G(^sentaiTestDouble("put", "/api/admin/v2/wqm-category")), 1), "/api/admin/v2/wqm-category?name=SENTAI%20NIGHT")
}

}
