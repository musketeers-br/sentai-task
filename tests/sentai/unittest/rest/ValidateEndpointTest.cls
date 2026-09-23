Class sentai.unittest.rest.ValidateEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method TestFullyValidFlowReturnsNoErrors()
{
    // Spec 004: the canonical flow's purge/journal steps are unavailable in v1; the fully valid
    // flow is the integrity-check-only one.
    Set id = ..CreateSupportedFlow("ValidateEndpointOk")
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ValidateFlow(id)
    Do $$$AssertEquals(%response.Status, 200)
}

Method TestInvalidFlowReturnsPopulatedReportButStill200()
{
    Set payload = ..CanonicalFlowPayload("ValidateEndpointBad")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ValidateFlow(id)
    // /validate itself always answers 200 with a report — errors block scheduling/dispatch
    // elsewhere, never the validation read itself (openapi.yaml).
    Do $$$AssertEquals(%response.Status, 200)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertNotTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))
}

/// Spec 004 FR-006 over the endpoint: /validate passes the operator's credential, so an unknown
/// category is reported (the endpoint still answers 200 with the report).
Method TestUnknownCategoryReportedOverHttp()
{
    Set payload = ..SupportedGraphPayload("ValidateEndpointCategory")
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) { Do s.%Set("wqmCategory", "NONEXISTENT") }
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set %session("sentai.bearerToken") = "test-token"
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ValidateFlow(id)
    Kill %session
    Do $$$AssertEquals(%response.Status, 200)
    // The same report the endpoint wrote, with the credential it used.
    Set report = ##class(sentai.validation.FlowValidator).Validate(id, "test-token")
    Set found = 0
    Set iter2 = report."errors".%GetIterator()
    While iter2.%GetNext(.k, .e) { If (e.code = "CATEGORY_NOT_FOUND") Set found = found + 1 }
    Do $$$AssertEquals(found, 3)
    // The endpoint really read the platform list with that credential.
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", "/api/admin/v2/wqm-categories")), "test-token")
}

}
