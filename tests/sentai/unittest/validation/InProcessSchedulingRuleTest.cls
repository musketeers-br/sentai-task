/// Spec 005 T010 (plan ID-3): in-process steps run as the dispatching operator, and a scheduled
/// run has no operator — /schedule refuses them; /validate and /dispatch do not.
Class sentai.unittest.validation.InProcessSchedulingRuleTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Codes(errors As %DynamicArray, stepId As %String) As %String
{
    Set codes = ""
    Set iter = errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Set:(e.stepId = stepId) codes = codes_","_e.code
    }
    Quit codes_","
}

Method TestScheduleRefusesAnInProcessStep()
{
    Set id = ..CreateFlowOf("InProcSchedule", [{"id": "01", "type": "db-size-report"}, {"id": "02", "type": "integrity-check"}], [{"source": "01", "target": "02"}])

    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Do $$$AssertTrue(..Codes(report.errors, "01") [ ",IN_PROCESS_NOT_SCHEDULABLE,")
    Do $$$AssertNotTrue(..Codes(report.errors, "02") [ ",IN_PROCESS_NOT_SCHEDULABLE,")
    Set iter = report.errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Continue:(e.code '= "IN_PROCESS_NOT_SCHEDULABLE")
        Do $$$AssertEquals(e.message, "Step '01' (db-size-report) runs inside the platform as the dispatching operator and cannot run in a scheduled run")
    }

    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"scheduleSpec": "WEEKLY SAT 03:00"}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
    Do $$$AssertEquals(+$G(^sentaiTestDouble("postlog")), 0)
}

Method TestValidateDoesNotReportIt()
{
    Set id = ..CreateFlowOf("InProcValidate", [{"id": "01", "type": "db-size-report"}])
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(report.errors.%Size(), 0, report.errors.%ToJSON())
}

}
