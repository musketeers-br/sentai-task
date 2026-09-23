Class sentai.unittest.rest.DispatchEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method NewRequest(bodyObj As %DynamicObject) As %Status
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write(bodyObj.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Quit $$$OK
}

Method TestValidDispatchReturns202WithAllStepsQueued()
{
    Set id = ..CreateSupportedFlow("DispatchOk")
    Do ..NewRequest({"confirmations": []})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 202)

    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai_model.StepRun sr JOIN sentai_model.Run r ON sr.run = r.ID WHERE r.flow = ?")
    Set result = rs.%Execute(id)
    Do result.%Next()
    Do $$$AssertEquals(result.%Get("c"), 3)
}

/// FR-017 still holds: a destructive step without a matching typed confirmation is named as
/// pending. Since spec 004 no v1-available type is destructive, so over HTTP the canonical flow
/// is refused earlier, by validation (422), and never reaches the 428 path.
Method TestMissingDestructiveConfirmationNamesStep()
{
    Set id = ..CreateCanonicalFlow("DispatchNoConfirm")
    Do $$$AssertNotTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, [], .pending))
    Do $$$AssertEquals(pending, "04")
    Do $$$AssertTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, ..CanonicalConfirmations(), .pending))

    Do ..NewRequest({"confirmations": []})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 422)

    // No StepRun should exist for this flow's steps.
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai_model.StepRun sr JOIN sentai_model.Run r ON sr.run = r.ID WHERE r.flow = ?")
    Set result = rs.%Execute(id)
    Do result.%Next()
    Do $$$AssertEquals(result.%Get("c"), 0)
}

Method TestStructuralErrorBlocksDispatchRegardlessOfPriorValidation()
{
    Set payload = ..CanonicalFlowPayload("DispatchStructBad")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Do ..NewRequest({"confirmations": [{"stepId": "04", "typedName": "%SYS"}]})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
}

}
