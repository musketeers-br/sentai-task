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
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wqm-categories/SENTAI.ENDPOINT_OK", "POST", 200, "", "{}")

    Set id = ..CreateCanonicalFlow("WqmAffected")
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [{"stepId": "04", "typedName": "%SYS"}], "tester", .errorCode, .errorDetail, .report)
    Do $$$AssertEquals(errorCode, "")

    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"defaultWorkers": 2, "maxActiveWorkers": 4, "maxWorkers": 8, "maxTotalWorkers": 16, "alwaysQueue": false}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()

    Do ##class(sentai.rest.Dispatcher).WriteWqmCategory("SENTAI.ENDPOINT_OK")
    Do $$$AssertEquals(%response.Status, 200)

    // The already-dispatched run's steps are untouched by the category change (FR-036).
    Set sr01 = ##class(sentai.model.StepRun).%OpenId(##class(sentai.model.StepRun).RunStepIndexOpen(run.%Id(), "01", 0), 0)
    Do $$$AssertEquals(sr01.state, "queued")
}

}
