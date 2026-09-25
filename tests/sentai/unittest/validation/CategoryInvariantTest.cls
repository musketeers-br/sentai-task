Class sentai.unittest.validation.CategoryInvariantTest Extends sentai.unittest.SentaiTestCase
{

Method TestViolatingInvariantIsRejectedAsErrorNeverWarning()
{
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(10, 5, 20, 30), 0)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(5, 10, 20, 30), 1)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(5, 10, 30, 20), 0)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(5, 25, 20, 30), 0)
}

/// Config.WorkQueues: "MaxTotalWorkers — if non-zero, specifies the maximum number of workers".
/// 0 is "no ceiling", so the platform's built-in Default (20/40/40/0) must satisfy the invariant.
Method TestZeroMaxTotalWorkersMeansNoCeiling()
{
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(20, 40, 40, 0), 1)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(50, 40, 40, 0), 0)
}

Method TestWriteServiceBlocksBeforeAnyAdminApiCall()
{
    Set payload = {}
    Do payload.%Set("name", "SENTAI.INVARIANT_TEST")
    Do payload.%Set("defaultWorkers", 50)
    Do payload.%Set("maxActiveWorkers", 5)
    Do payload.%Set("maxWorkers", 10)
    Do payload.%Set("maxTotalWorkers", 20)
    Do payload.%Set("alwaysQueue", 0)

    Set sc = ##class(sentai.wqm.CategoryService).Write(payload, "fake-token")
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "SentaiInvariantViolated")
}

}
