Class sentai.unittest.model.StepTest Extends sentai.unittest.SentaiTestCase
{

Method TestIsDestructiveIsAlwaysDerivedNeverWritable()
{
    Set id = ..CreateCanonicalFlow("StepDestr")
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(id, "04", 0)
    Do $$$AssertEquals(step.type, "purge-audit-records")
    Do $$$AssertEquals(step.isDestructive, 1)

    Set step1 = ##class(sentai.model.Step).FlowStepIndexOpen(id, "01", 0)
    Do $$$AssertEquals(step1.isDestructive, 0)
}

Method TestIsDestructiveIgnoredEvenIfPayloadClaimsOtherwise()
{
    // sentai.model.Step has no writable isDestructive property at all — attempting to set
    // it is a compile-time impossibility, which is the strongest form of "never accepted
    // as operator input" (FR-010). This test documents that guarantee by asserting the
    // computed value ignores anything in Step.parameters that might try to smuggle it in.
    Set id = ..CreateCanonicalFlow("StepDestrIgnore")
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(id, "01", 4)
    Set step.parameters = {"isDestructive": true}
    Do step.%Save()
    Do $$$AssertEquals(step.isDestructive, 0)
}

}
