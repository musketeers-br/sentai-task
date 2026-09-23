Class sentai.unittest.validation.NamespaceRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestNonExistentNamespaceIsAnError()
{
    Set payload = ..CanonicalFlowPayload("BadNamespace")
    Set steps = []
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.id = "01") Do s.%Set("namespace", "SENTAI_DOES_NOT_EXIST")
        Do steps.%Push(s)
    }
    Do payload.%Set("steps", steps)

    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter2 = report."errors".%GetIterator()
    While iter2.%GetNext(.k, .e) {
        If (e.code = "NAMESPACE_NOT_FOUND") && (e.stepId = "01") Set found = 1
    }
    Do $$$AssertTrue(found)
}

Method TestExistingNamespacePassesThisRule()
{
    // %SYS always exists on any IRIS instance.
    Set id = ..CreateCanonicalFlow("GoodNamespace")
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "NAMESPACE_NOT_FOUND") && (e.stepId = "04") Set found = 1
    }
    Do $$$AssertNotTrue(found)
}

}
