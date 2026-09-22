Class sentai.unittest.validation.CustomStepRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestCustomStepWithNoClassIsAlwaysAnError()
{
    Set payload = ..CanonicalFlowPayload("CustomNoClass")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom step", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "CUSTOM_CLASS_REQUIRED") && (e.stepId = "06") Set found = 1
    }
    Do $$$AssertTrue(found)

    Set foundAsWarning = 0
    Set iter2 = report."warnings".%GetIterator()
    While iter2.%GetNext(.k, .w) {
        If (w.code = "CUSTOM_CLASS_REQUIRED") Set foundAsWarning = 1
    }
    Do $$$AssertFalse(foundAsWarning)
}

Method TestCustomStepWithClassDeclaredDoesNotTriggerThisRule()
{
    Set payload = ..CanonicalFlowPayload("CustomWithClass")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom step", "namespace": "USER", "customClass": "sentai.unittest.FakeCustomTask"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "CUSTOM_CLASS_REQUIRED") Set found = 1
    }
    Do $$$AssertFalse(found)
}

}
