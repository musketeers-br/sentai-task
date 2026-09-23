Class sentai.unittest.model.FlowTest Extends sentai.unittest.SentaiTestCase
{

Method TestDuplicateNameIsRejectedCaseInsensitive()
{
    Set payload1 = ..CanonicalFlowPayload("DupCheck")
    Set sc1 = ##class(sentai.model.Flow).SaveGraph(payload1, "", 0, "tester", .id1)
    Do $$$AssertStatusOK(sc1)

    Set payload2 = {}.%FromJSON(payload1.%ToJSON())
    Do payload2.%Set("name", $ZCONVERT(payload1.name, "U"))
    Set sc2 = ##class(sentai.model.Flow).SaveGraph(payload2, "", 0, "tester", .id2)
    Do $$$AssertStatusNotOK(sc2)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc2) [ "SentaiNameConflict")
}

Method TestRevisionIncrementsOnEverySave()
{
    Set id = ..CreateCanonicalFlow("RevBump")
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Do $$$AssertEquals(flow.revision, 1)

    Set payload = ..CanonicalFlowPayload("RevBump")
    Do payload.%Set("name", flow.name)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, id, 1, "tester", .savedId)
    Do $$$AssertStatusOK(sc)

    Set flow2 = ##class(sentai.model.Flow).%OpenId(savedId, 0)
    Do $$$AssertEquals(flow2.revision, 2)
}

Method TestStaleRevisionSaveIsRejected()
{
    Set id = ..CreateCanonicalFlow("StaleRev")
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)

    Set payload = ..CanonicalFlowPayload("StaleRev")
    Do payload.%Set("name", flow.name)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, id, 999, "tester", .savedId)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "SentaiStaleRevision")
}

}
