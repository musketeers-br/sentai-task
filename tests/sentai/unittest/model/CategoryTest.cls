Class sentai.unittest.model.CategoryTest Extends sentai.unittest.SentaiTestCase
{

Method TestWriteIsAlwaysAPassthroughToTheAdministrativeApi()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wqm-categories/SENTAI.MIRROR_TEST", "POST", 200, "", "{}")

    Set payload = {}
    Do payload.%Set("name", "SENTAI.MIRROR_TEST")
    Do payload.%Set("defaultWorkers", 2)
    Do payload.%Set("maxActiveWorkers", 4)
    Do payload.%Set("maxWorkers", 8)
    Do payload.%Set("maxTotalWorkers", 16)
    Do payload.%Set("alwaysQueue", 0)

    Set sc = ##class(sentai.wqm.CategoryService).Write(payload, "fake-token")
    Do $$$AssertStatusOK(sc)

    Set catId = ##class(sentai.model.Category).NameIndexOpen("SENTAI.MIRROR_TEST", 0)
    Set cat = ##class(sentai.model.Category).%OpenId(catId, 0)
    Do $$$AssertEquals(cat.maxTotalWorkers, 16)
}

Method TestInvariantViolationNeverReachesTheAdminApiCall()
{
    Set payload = {}
    Do payload.%Set("name", "SENTAI.MIRROR_BAD")
    Do payload.%Set("defaultWorkers", 20)
    Do payload.%Set("maxActiveWorkers", 4)
    Do payload.%Set("maxWorkers", 8)
    Do payload.%Set("maxTotalWorkers", 16)
    Do payload.%Set("alwaysQueue", 0)

    Set sc = ##class(sentai.wqm.CategoryService).Write(payload, "fake-token")
    Do $$$AssertStatusNotOK(sc)

    // No local mirror row should have been created for a rejected write.
    Set catId = ##class(sentai.model.Category).NameIndexOpen("SENTAI.MIRROR_BAD", 0)
    Do $$$AssertEquals(catId, "")
}

}
