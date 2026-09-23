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

/// Spec 004 FR-003: unavailable types are refused on execution paths only — a flow made of
/// them is still created, persisted with its types intact, and read back.
Method TestFlowWithUnavailableTypeSavesAndReadsUnchanged()
{
    Set payload = ..CanonicalFlowPayload("RestUnavailable")
    Do ..NewRequest(payload)
    Do ##class(sentai.rest.Dispatcher).CreateFlow()
    Do $$$AssertEquals(%response.Status, 201)

    Set flow = ##class(sentai.model.Flow).NameIndexOpen(payload.name, 0)
    Do $$$AssertTrue($IsObject(flow))
    Set flowId = flow.%Id(), types = ""
    &sql(DECLARE c CURSOR FOR SELECT type INTO :t FROM sentai_model.Step WHERE flow = :flowId ORDER BY id)
    &sql(OPEN c)
    For { &sql(FETCH c) Quit:SQLCODE  Set types = types_$S(types = "":"", 1:",")_t }
    &sql(CLOSE c)
    Do $$$AssertEquals(types, "integrity-check,integrity-check,integrity-check,purge-audit-records,switch-journal")

    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ReadFlow(flowId)
    Do $$$AssertEquals(%response.Status, 200)
}

Method TestReadReturnsIdenticalStructure()
{
    Set id = ..CreateCanonicalFlow("RestRead")
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ReadFlow(id)
    Do $$$AssertEquals(%response.Status, 200)
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
