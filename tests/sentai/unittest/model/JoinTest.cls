Class sentai.unittest.model.JoinTest Extends sentai.unittest.SentaiTestCase
{

Method TestJoinEntryExistsForFanInTargetWithAllMustSucceedPolicy()
{
    Set id = ..CreateCanonicalFlow("JoinCheck")
    // Step 04 has three incoming edges (01, 02, 03) — a join entry MUST exist for it.
    Set join = ##class(sentai.model.Join).FlowTargetIndexOpen(id, "04", 0)
    Do $$$AssertTrue($IsObject(join))
    Do $$$AssertEquals(join.policy, "ALL_MUST_SUCCEED")
}

Method TestNoJoinEntryForSingleIncomingEdgeTarget()
{
    Set id = ..CreateCanonicalFlow("NoJoinCheck")
    // Step 05 has exactly one incoming edge (from 04) — no join entry is expected.
    Do $$$AssertNotTrue(##class(sentai.model.Join).FlowTargetIndexExists(id, "05"))
}

}
