Class sentai.unittest.validation.ParameterSchemaRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestPurgeAuditRecordsWithoutDaysToKeepIsAnError()
{
    Set payload = ..CanonicalFlowPayload("ParamMissing")
    // Overwrite step 04 (purge-audit-records) so its parameters omit daysToKeep.
    Set steps = []
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.id = "04") {
            Do s.%Remove("parameters")
        }
        Do steps.%Push(s)
    }
    Do payload.%Set("steps", steps)

    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter2 = report."errors".%GetIterator()
    While iter2.%GetNext(.k, .e) {
        If (e.code = "PARAMETER_SCHEMA") && (e.stepId = "04") Set found = 1
    }
    Do $$$AssertTrue(found)
}

Method TestPurgeAuditRecordsWithDaysToKeepPassesThisRule()
{
    Set id = ..CreateCanonicalFlow("ParamOk")
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "PARAMETER_SCHEMA") Set found = 1
    }
    Do $$$AssertNotTrue(found)
}

}
