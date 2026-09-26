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

/// --- Spec 005 T008: declared parameter schemas (FR-005, contracts/api-delta.md) ---
/// The rule receives the schema and the class as arguments; Validate passes the catalog's.
ClassMethod Findings(type As %String, parameters As %DynamicObject, schema As %DynamicArray = "", className As %String = "sentai.unittest.fixtures.FakeOk") As %DynamicArray
{
    Set:(schema = "") schema = ##class(sentai.registry.StepType).GetParameterSchema(type)
    Set errors = []
    Do ##class(sentai.validation.FlowValidator).DeclaredStepFindings("01", type, schema, parameters, className, errors)
    Quit errors
}

/// The single finding of `code` in `errors` ("" when absent).
ClassMethod Only(errors As %DynamicArray, code As %String) As %DynamicObject
{
    Set found = ""
    Set iter = errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Set:(e.code = code) found = e
    }
    Quit found
}

Method TestUnknownParameter()
{
    Set errors = ..Findings("storage-headroom-check", {"path": "/etc"})
    Do $$$AssertEquals(errors.%Size(), 1)
    Set e = ..Only(errors, "PARAM_UNKNOWN")
    Do $$$AssertTrue($IsObject(e))
    Do $$$AssertEquals(e.stepId, "01")
    Do $$$AssertEquals(e.parameter, "path")
    Do $$$AssertEquals(e.message, "Step '01' (storage-headroom-check): unknown parameter 'path'")
    // An empty declared schema makes every key unknown.
    Do $$$AssertEquals(..Only(..Findings("db-size-report", {"path": "/etc"}), "PARAM_UNKNOWN").parameter, "path")
}

Method TestTypeMismatch()
{
    Set e = ..Only(..Findings("storage-headroom-check", {"minFreePercent": "ten"}), "PARAM_TYPE_MISMATCH")
    Do $$$AssertTrue($IsObject(e))
    Do $$$AssertEquals(e.parameter, "minFreePercent")
    Do $$$AssertEquals(e.message, "Step '01' (storage-headroom-check): parameter 'minFreePercent' must be a number")
    Set schema = [{"name": "keepDays", "property": "KeepDays", "type": "integer", "required": false}]
    Set e = ..Only(..Findings("purge-task-history", {"keepDays": 2.5}, schema), "PARAM_TYPE_MISMATCH")
    Do $$$AssertEquals(e.message, "Step '01' (purge-task-history): parameter 'keepDays' must be an integer")
    Do $$$AssertEquals(..Findings("purge-task-history", {"keepDays": 30}, schema).%Size(), 0)
    Set schema = [{"name": "flag", "property": "Flag", "type": "boolean", "required": false}]
    Do $$$AssertTrue($IsObject(..Only(..Findings("x", {"flag": 1}, schema), "PARAM_TYPE_MISMATCH")))
    Do $$$AssertEquals(..Findings("x", {"flag": true}, schema).%Size(), 0)
}

Method TestOutOfRange()
{
    Set e = ..Only(..Findings("storage-headroom-check", {"minFreePercent": 150}), "PARAM_OUT_OF_RANGE")
    Do $$$AssertTrue($IsObject(e))
    Do $$$AssertEquals(e.parameter, "minFreePercent")
    Do $$$AssertEquals(e.message, "Step '01' (storage-headroom-check): parameter 'minFreePercent' must be between 0 and 100")
    Do $$$AssertTrue($IsObject(..Only(..Findings("storage-headroom-check", {"minFreePercent": -1}), "PARAM_OUT_OF_RANGE")))
    Do $$$AssertEquals(..Findings("storage-headroom-check", {"minFreePercent": 100}).%Size(), 0)
    Do $$$AssertEquals(..Findings("storage-headroom-check", {}).%Size(), 0, "optional, default applies")
}

Method TestRequired()
{
    Set schema = [{"name": "keepDays", "property": "KeepDays", "type": "integer", "required": true, "min": 0}]
    Set e = ..Only(..Findings("purge-task-history", {}, schema), "PARAM_REQUIRED")
    Do $$$AssertTrue($IsObject(e))
    Do $$$AssertEquals(e.parameter, "keepDays")
    Do $$$AssertEquals(e.message, "Step '01' (purge-task-history): parameter 'keepDays' is required")
    Do $$$AssertEquals(..Findings("purge-task-history", "", schema).%Size(), 1, "no parameters object at all")
}

Method TestDeclaredClassNotInstalled()
{
    Set errors = ..Findings("db-size-report", {}, "", "sentai.steps.DoesNotExist")
    Set e = ..Only(errors, "STEP_TYPE_NOT_SUPPORTED_ON_TARGET")
    Do $$$AssertTrue($IsObject(e))
    Do $$$AssertEquals(e.message, "Step type 'db-size-report' is not supported on the target platform: its declared class is not installed")
    Do $$$AssertTrue($IsObject(..Only(..Findings("db-size-report", {}, "", "sentai.unittest.SentaiTestCase"), "STEP_TYPE_NOT_SUPPORTED_ON_TARGET")), "not a task")
    Do $$$AssertEquals(..Findings("db-size-report", {}, "", "sentai.unittest.fixtures.FakeOk").%Size(), 0)
}

/// End to end: the catalog's schema is applied by Validate, and the refusal holds on dispatch
/// (no run) and on schedule (422).
Method TestViolationRefusedOnValidateDispatchAndSchedule()
{
    Set id = ..CreateFlowOf("ParamUnknownE2E", [{"id": "01", "type": "db-size-report", "parameters": {"path": "/etc"}}])
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(..Only(report.errors, "PARAM_UNKNOWN").stepId, "01")

    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .ec, .ed, .rep)
    Do $$$AssertEquals(ec, "VALIDATION_FAILED")
    &sql(SELECT COUNT(*) INTO :runs FROM sentai_model.Run WHERE flow = :id)
    Do $$$AssertEquals(runs, 0)

    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"scheduleSpec": "WEEKLY SAT 03:00"}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
}

/// Spec 007 BD-1/BD-2: purge-audit-records keeps exactly one finding for a missing daysToKeep
/// (its existing PARAMETER_SCHEMA, now naming the parameter) — its schema is declared for the
/// canvas only and the PARAM_* rules are for in-process types.
Method TestPurgeAuditMissingDaysToKeepHasOneFindingNamingIt()
{
    Set id = ..CreateFlowOf("ParamPurgeAudit", [{"id": "01", "type": "purge-audit-records", "namespace": "%SYS"}])
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set n = 0, finding = ""
    Set iter = report.errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Continue:(e.code = "STEP_TYPE_NOT_SUPPORTED_ON_TARGET")
        Set n = n + 1, finding = e
    }
    Do $$$AssertEquals(n, 1)
    Do $$$AssertEquals(finding.code, "PARAMETER_SCHEMA")
    Do $$$AssertEquals(finding.parameter, "daysToKeep")
}

}
