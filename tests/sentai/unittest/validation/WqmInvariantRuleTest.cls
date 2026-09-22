Class sentai.unittest.validation.WqmInvariantRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestCategoryViolatingInvariantIsAnError()
{
    Do ##class(sentai.model.Category).Mirror("SENTAI.BROKEN", 10, 5, 20, 30, 0)

    Set payload = ..CanonicalFlowPayload("WqmInvariantBad")
    Set steps = []
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.id = "01") Do s.%Set("wqmCategory", "SENTAI.BROKEN")
        Do steps.%Push(s)
    }
    Do payload.%Set("steps", steps)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter2 = report."errors".%GetIterator()
    While iter2.%GetNext(.k, .e) {
        If (e.code = "WQM_INVARIANT_VIOLATED") && (e.stepId = "01") Set found = 1
    }
    Do $$$AssertTrue(found)
}

Method TestCategorySatisfyingInvariantPassesThisRule()
{
    Do ##class(sentai.model.Category).Mirror("SENTAI.GOOD", 5, 10, 20, 30, 0)

    Set payload = ..CanonicalFlowPayload("WqmInvariantGood")
    Set steps = []
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.id = "01") Do s.%Set("wqmCategory", "SENTAI.GOOD")
        Do steps.%Push(s)
    }
    Do payload.%Set("steps", steps)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter2 = report."errors".%GetIterator()
    While iter2.%GetNext(.k, .e) {
        If (e.code = "WQM_INVARIANT_VIOLATED") Set found = 1
    }
    Do $$$AssertFalse(found)
}

}
