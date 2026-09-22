Class sentai.unittest.rest.ScheduleEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method TestScheduleValidatedFlowReturns201WithOneTaskIdPerStep()
{
    Set id = ..CreateCanonicalFlow("ScheduleOk")
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"scheduleSpec": "WEEKLY SAT 03:00", "category": "SENTAI.NIGHT"}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()

    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 201)
}

Method TestSchedulingFlowWithValidationErrorIsRefused()
{
    Set payload = ..CanonicalFlowPayload("ScheduleBad")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"scheduleSpec": "WEEKLY SAT 03:00"}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()

    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
}

}
