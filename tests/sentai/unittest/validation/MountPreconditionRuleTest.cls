Class sentai.unittest.validation.MountPreconditionRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestReadOnlyDirectoryProducesWarningNotError()
{
    Set payload = ..CanonicalFlowPayload("ReadOnlyMount")
    Set steps = []
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        // A path that cannot possibly be writable by the process — exercises the "probe
        // write fails" branch of IsMountedReadOnly without depending on real IRIS mount
        // configuration.
        If (s.id = "01") Do s.%Set("databaseDirectory", "/this/path/does/not/exist/at/all")
        Do steps.%Push(s)
    }
    Do payload.%Set("steps", steps)

    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)

    Set foundWarning = 0
    Set iter2 = report."warnings".%GetIterator()
    While iter2.%GetNext(.k, .w) {
        If (w.code = "PRECONDITION_READ_ONLY") && (w.stepId = "01") Set foundWarning = 1
    }
    Do $$$AssertTrue(foundWarning)

    Set foundError = 0
    Set iter3 = report."errors".%GetIterator()
    While iter3.%GetNext(.k, .e) {
        If (e.code = "PRECONDITION_READ_ONLY") Set foundError = 1
    }
    Do $$$AssertNotTrue(foundError)
}

Method TestReadOnlyWarningDoesNotBlockValidation()
{
    Set payload = ..CanonicalFlowPayload("ReadOnlyDoesNotBlock")
    Set steps = []
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.id = "01") Do s.%Set("databaseDirectory", "/this/path/does/not/exist/at/all")
        Do steps.%Push(s)
    }
    Do payload.%Set("steps", steps)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))
}

}
