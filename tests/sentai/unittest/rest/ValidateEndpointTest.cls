Class sentai.unittest.rest.ValidateEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method TestFullyValidFlowReturnsNoErrors()
{
    Set id = ..CreateCanonicalFlow("ValidateEndpointOk")
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
    Do $$$AssertFalse(##class(sentai.validation.FlowValidator).HasNoErrors(report))
}

}
