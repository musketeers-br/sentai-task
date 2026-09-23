Class sentai.unittest.validation.CategoryInvariantTest Extends sentai.unittest.SentaiTestCase
{

Method TestViolatingInvariantIsRejectedAsErrorNeverWarning()
{
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(10, 5, 20, 30), 0)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(5, 10, 20, 30), 1)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(5, 10, 30, 20), 0)
    Do $$$AssertEquals(##class(sentai.model.Category).SatisfiesInvariant(5, 25, 20, 30), 0)
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

/// Spec 004 D-3 / FR-005: 0 in maxWorkers or maxTotalWorkers means unbounded (+inf); only those
/// two fields. Rows from specs/004-backend-hardening/data-model.md.
Method TestZeroMaxWorkersOrMaxTotalMeansUnbounded()
{
    Set C = "sentai.model.Category"
    Do $$$AssertEquals($CLASSMETHOD(C, "SatisfiesInvariant", 1, 3, 0, 0), 1, "built-in Utility (evidence 10a)")
    Do $$$AssertEquals($CLASSMETHOD(C, "SatisfiesInvariant", 2, 4, 8, 0), 1, "finite maxWorkers under unbounded total")
    Do $$$AssertEquals($CLASSMETHOD(C, "SatisfiesInvariant", 1, 2, 0, 5), 0, "unbounded maxWorkers over finite total")
    Do $$$AssertEquals($CLASSMETHOD(C, "SatisfiesInvariant", 1, 2, 3, 2), 0, "non-zero violation unchanged")
    Do $$$AssertEquals($CLASSMETHOD(C, "SatisfiesInvariant", 0, 0, 0, 0), 1, "all zero")
    Do $$$AssertEquals($CLASSMETHOD(C, "SatisfiesInvariant", 5, 3, 0, 0), 0, "defaultWorkers > maxActiveWorkers still violates")
}

}
