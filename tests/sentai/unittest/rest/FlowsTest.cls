/// Exercises sentai.rest.Dispatcher's /flows methods directly (bypassing the CSP HTTP
/// layer itself, which quickstart.md validates against a real instance), asserting the
/// %response.Status this plan's contracts/rest-mapping.md promises for each scenario.
Class sentai.unittest.rest.FlowsTest Extends sentai.unittest.SentaiTestCase
{

Method NewRequest(bodyObj As %DynamicObject) As %Status
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write(bodyObj.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Quit $$$OK
}

Method TestCreateReturns201WithIdAndRevision1()
{
    Set payload = ..CanonicalFlowPayload("RestCreate")
    Do ..NewRequest(payload)
    Do ##class(sentai.rest.Dispatcher).CreateFlow()
    Do $$$AssertEquals(%response.Status, 201)
}

Method TestReadReturnsIdenticalStructure()
{
    Set id = ..CreateCanonicalFlow("RestRead")
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ReadFlow(id)
    Do $$$AssertEquals(%response.Status, 200)
}

/// Step.parameters is part of the openapi.yaml Step schema; without it a read → save round
/// trip from the canvas silently drops e.g. daysToKeep and the flow stops validating.
Method TestReadReturnsStepParameters()
{
    Set id = ..CreateCanonicalFlow("RestParams")
    Set shaped = ##class(sentai.rest.Dispatcher).ShapeFlow(##class(sentai.model.Flow).%OpenId(id, 0), 1)
    Set purge = ""
    Set iter = shaped."steps".%GetIterator()
    While iter.%GetNext(.k, .step) {
        If (step.id = "04") Set purge = step
    }
    Do $$$AssertTrue($IsObject(purge), "step 04 is returned")
    Do $$$AssertTrue($IsObject(purge) && $IsObject(purge.parameters), "step 04 carries its parameters object")
    Do $$$AssertEquals($S($IsObject(purge) && $IsObject(purge.parameters):purge.parameters.daysToKeep, 1:""), 30)
}

Method TestSaveAgainstStaleRevisionReturns409()
{
    Set id = ..CreateCanonicalFlow("RestStale")
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Set payload = ..CanonicalFlowPayload("RestStale")
    Do payload.%Set("name", flow.name)
    Do ..NewRequest(payload)
    Set %request.Data("revision", 1) = 999
    Do ##class(sentai.rest.Dispatcher).SaveFlow(id)
    Do $$$AssertEquals(%response.Status, 409)
}

Method TestDuplicateNameReturns409()
{
    Set payload1 = ..CanonicalFlowPayload("RestDup")
    Do ..NewRequest(payload1)
    Do ##class(sentai.rest.Dispatcher).CreateFlow()
    Do $$$AssertEquals(%response.Status, 201)

    Set payload2 = {}.%FromJSON(payload1.%ToJSON())
    Do ..NewRequest(payload2)
    Do ##class(sentai.rest.Dispatcher).CreateFlow()
    Do $$$AssertEquals(%response.Status, 409)
}

Method TestCycleClosingEdgeOnSaveReturns422()
{
    Set id = ..CreateCanonicalFlow("RestCycle422")
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Set payload = ..CanonicalFlowPayload("RestCycle422")
    Do payload.%Set("name", flow.name)
    Do payload."edges".%Push({"source": "05", "target": "01"})
    Do ..NewRequest(payload)
    Set %request.Data("revision", 1) = 1
    Do ##class(sentai.rest.Dispatcher).SaveFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
}

}
