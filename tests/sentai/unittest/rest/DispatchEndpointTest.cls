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
    Set id = ..CreateCanonicalFlow("DispatchOk")
    Do ..NewRequest({"confirmations": [{"stepId": "04", "typedName": "%SYS"}]})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 202)

    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai.model.StepRun sr JOIN sentai.model.Run r ON sr.run = r.ID WHERE r.flow = ?")
    Set result = rs.%Execute(id)
    Do result.%Next()
    Do $$$AssertEquals(result.%Get("c"), 5)
}

Method TestMissingDestructiveConfirmationReturns428NamingStep()
{
    Set id = ..CreateCanonicalFlow("DispatchNoConfirm")
    Do ..NewRequest({"confirmations": []})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 428)

    // No StepRun should exist for this flow's steps.
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai.model.StepRun sr JOIN sentai.model.Run r ON sr.run = r.ID WHERE r.flow = ?")
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
