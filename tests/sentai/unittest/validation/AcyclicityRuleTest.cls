Class sentai.unittest.validation.AcyclicityRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestDirectlyInjectedCycleProducesError()
{
    Set id = ..CreateCanonicalFlow("ValidateCycle")

    // Inject a cycle-closing edge directly at the persistence layer, bypassing the
    // mutation-time guard (data-model.md), the way the independent test for User
    // Story 2 requires ("a cycle introduced by directly editing the contract").
    Set edge = ##class(sentai.model.Edge).%New()
    Do edge.flowSetObjectId(id)
    Set edge.source = "05"
    Set edge.target = "01"
    Do edge.%Save()

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "CYCLE_DETECTED") Set found = 1
    }
    Do $$$AssertTrue(found)
}

}
