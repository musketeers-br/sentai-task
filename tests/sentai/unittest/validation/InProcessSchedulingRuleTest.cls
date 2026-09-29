/// Spec 005 T010 made in-process steps unschedulable (a scheduled run had no operator). Spec 015
/// D-6: a scheduled run now acts as its run-as account, so they are schedulable; the rule is gone.
Class sentai.unittest.validation.InProcessSchedulingRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestScheduleAllowsAnInProcessStep()
{
    Set id = ..CreateFlowOf("InProcSchedule", [{"id": "01", "type": "db-size-report"}, {"id": "02", "type": "integrity-check"}], [{"source": "01", "target": "02"}])
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Do $$$AssertNotTrue(report.%ToJSON() [ "IN_PROCESS_NOT_SCHEDULABLE")
    Do $$$AssertEquals(report.errors.%Size(), 0, report.errors.%ToJSON())
}

Method TestValidateDoesNotReportIt()
{
    Set id = ..CreateFlowOf("InProcValidate", [{"id": "01", "type": "db-size-report"}])
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(report.errors.%Size(), 0, report.errors.%ToJSON())
}

}
