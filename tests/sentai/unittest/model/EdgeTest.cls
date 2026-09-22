Class sentai.unittest.model.EdgeTest Extends sentai.unittest.SentaiTestCase
{

Method TestCycleClosingEdgeIsRejectedAtMutationTime()
{
    Set id = ..CreateCanonicalFlow("CycleCheck")
    // 05 (journal switch, the terminal step) -> 01 would close a cycle: 01->04->05->01.
    Do $$$AssertEquals(##class(sentai.model.Edge).WouldCreateCycle(id, "05", "01"), 1)
}

Method TestNonCyclicEdgeIsAccepted()
{
    Set id = ..CreateCanonicalFlow("NoCycleCheck")
    Do $$$AssertEquals(##class(sentai.model.Edge).WouldCreateCycle(id, "02", "05"), 0)
}

Method TestSelfLoopIsAlwaysACycle()
{
    Set id = ..CreateCanonicalFlow("SelfLoopCheck")
    Do $$$AssertEquals(##class(sentai.model.Edge).WouldCreateCycle(id, "01", "01"), 1)
}

Method TestReplaceAllRejectsWholeGraphCycleAndPersistsNothing()
{
    Set payload = ..CanonicalFlowPayload("WholeGraphCycle")
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set cyclicPayload = {}.%FromJSON(payload.%ToJSON())
    Do cyclicPayload.%Set("name", payload.name)
    Do cyclicPayload."edges".%Push({"source": "05", "target": "01"})

    Set sc2 = ##class(sentai.model.Flow).SaveGraph(cyclicPayload, id, 1, "tester", .savedId)
    Do $$$AssertStatusNotOK(sc2)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc2) [ "SentaiCycle")

    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Do $$$AssertEquals(flow.revision, 1)
}

}
