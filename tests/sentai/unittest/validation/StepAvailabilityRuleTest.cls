/// Spec 004 FR-002: a step whose type is in the catalog but not available on the target platform
/// (D-1: only integrity-check is) is refused on every execution path — validate, dispatch,
/// schedule and rerun — with STEP_TYPE_NOT_SUPPORTED_ON_TARGET, and nothing reaches the
/// administrative API (SC-001: 6 types x 4 paths = 24 refusals).
Class sentai.unittest.validation.StepAvailabilityRuleTest Extends sentai.unittest.SentaiTestCase
{

Parameter CODE = "STEP_TYPE_NOT_SUPPORTED_ON_TARGET";

/// A one-step flow of `type` on the built-in Default category, with whatever the type's other
/// rules need so that availability is the only finding.
Method SingleStepFlow(type As %String, namePrefix As %String = "Avail") As %String
{
    Set step = {"id": "01", "type": (type), "taskName": ("Step "_type), "namespace": "%SYS", "runAsUser": "irisadm", "timeoutMinutes": 5, "wqmCategory": "Default"}
    If (type = "purge-audit-records") Do step.%Set("parameters", {"daysToKeep": 30})
    If (type = "custom") Do step.%Set("customClass", "%SYS.Task.IntegrityCheck")
    Set payload = {
        "schemaVersion": 1,
        "name": (namePrefix_"-"_type_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)),
        "defaultCategory": "Default",
        "steps": [ (step) ],
        "edges": [],
        "joins": []
    }
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

ClassMethod ErrorsWithCode(report As %DynamicObject, code As %String, ByRef stepIds As %String) As %Integer
{
    Set n = 0, stepIds = ""
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        Continue:(e.code '= code)
        Set n = n + 1, stepIds = stepIds_$S(stepIds = "":"", 1:",")_e.stepId
    }
    Quit n
}

ClassMethod RunCountFor(flowId As %String) As %Integer
{
    &sql(SELECT COUNT(*) INTO :c FROM sentai_model.Run WHERE flow = :flowId)
    Quit +$G(c)
}

Method TestEveryUnavailableTypeIsRefusedOnAllFourPaths()
{
    Set refusals = 0
    For type = "compact-globals", "defragment-globals", "switch-journal", "purge-audit-records", "purge-task-history", "custom" {
        Set id = ..SingleStepFlow(type)

        // 1. validate
        Set report = ##class(sentai.validation.FlowValidator).Validate(id)
        Do $$$AssertEquals(..ErrorsWithCode(report, ..#CODE, .ids), 1, type_": one availability error")
        Do $$$AssertEquals(ids, "01")
        Set iter = report."errors".%GetIterator()
        While iter.%GetNext(.k, .e) {
            If (e.code = ..#CODE) Do $$$AssertTrue(e.message [ ("'"_type_"'"), type_": message names the type")
        }
        Set refusals = refusals + 1

        // 2. dispatch — refused by validation, never asking for a typed confirmation
        Set errorCode = "", errorDetail = "", vr = ""
        Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .errorCode, .errorDetail, .vr)
        Do $$$AssertEquals(errorCode, "VALIDATION_FAILED", type_": dispatch refused by validation")
        Do $$$AssertEquals(..ErrorsWithCode(vr, ..#CODE), 1)
        Do $$$AssertEquals(..RunCountFor(id), 0, type_": no run created")
        Set refusals = refusals + 1

        // 3. schedule — 422 over the endpoint, no native task
        Set %request = ##class(%CSP.Request).%New()
        Set %request.Content = ##class(%Stream.TmpCharacter).%New()
        Do %request.Content.Write({"scheduleSpec": "WEEKLY SAT 03:00"}.%ToJSON())
        Set %response = ##class(%CSP.Response).%New()
        Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
        Do $$$AssertEquals(%response.Status, 422, type_": schedule refused")
        Do $$$AssertEquals(..ErrorsWithCode(##class(sentai.validation.FlowValidator).ValidateForSchedule(id), ..#CODE), 1)
        Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
        Set refusals = refusals + 1

        // 4. rerun of a failed step of this type in a run that predates the rule
        Set run = ..DispatchUngated(id)
        Set sr = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
        Do sr.TransitionTo("running")
        Do sr.TransitionTo("failed", "simulated failure")
        Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, sr.guid, .newGuid)
        Do $$$AssertStatusNotOK(sc, type_": rerun refused")
        Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ..#CODE)
        Set runId = run.%Id(), srCount = ""
        &sql(SELECT COUNT(*) INTO :srCount FROM sentai_model.StepRun WHERE run = :runId)
        Do $$$AssertEquals(srCount, 1, type_": no new StepRun")
        Set refusals = refusals + 1
    }
    Do $$$AssertEquals(refusals, 24)

    // Nothing reached the administrative API on any path.
    Do $$$AssertEquals($D(^sentaiTestDouble("posted")), 0)
    Do $$$AssertEquals($D(^sentaiTestDouble("put")), 0)
}

Method TestMixedFlowReportsOnlyTheUnavailableStep()
{
    Set payload = ..SupportedGraphPayload("AvailMixed")
    Do payload."steps".%Push({"id": "04", "type": "purge-audit-records", "taskName": "Purge audit", "namespace": "%SYS", "runAsUser": "irisadm", "timeoutMinutes": 20, "wqmCategory": "Default", "parameters": {"daysToKeep": 30}})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(..ErrorsWithCode(report, ..#CODE, .ids), 1)
    Do $$$AssertEquals(ids, "04")
}

Method TestSupportedFlowHasNoErrors()
{
    Set report = ##class(sentai.validation.FlowValidator).Validate(..CreateSupportedFlow("AvailOk"))
    Do $$$AssertEquals(report."errors".%Size(), 0)
}

Method TestUnknownTypeReportsOnlyUnknownStepType()
{
    Set id = ..SingleStepFlow("bogus")
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(..ErrorsWithCode(report, "UNKNOWN_STEP_TYPE"), 1)
    Do $$$AssertEquals(..ErrorsWithCode(report, ..#CODE), 0)
}

Method TestCustomWithoutClassReportsBothErrors()
{
    Set payload = ..SupportedGraphPayload("AvailCustom")
    Do payload."steps".%Push({"id": "04", "type": "custom", "taskName": "Custom", "namespace": "USER", "wqmCategory": "Default"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(..ErrorsWithCode(report, "CUSTOM_CLASS_REQUIRED"), 1)
    Do $$$AssertEquals(..ErrorsWithCode(report, ..#CODE, .ids), 1)
    Do $$$AssertEquals(ids, "04")
}


/// Spec 006 D-4 (analysis R1): after the catalog names the real, compiled audit-purge class, the
/// type is still refused, because the refusal comes from `available: false`.
Method TestPurgeAuditStillRefusedAfterClassFix()
{
    Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(##class(sentai.registry.StepType).GetTargetClass("purge-audit-records")), "the corrected class is compiled")
    Set id = ..SingleStepFlow("purge-audit-records", "AvailD4")
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(..ErrorsWithCode(report, ..#CODE, .ids), 1)
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = ..#CODE) Do $$$AssertTrue(e.message [ "'purge-audit-records' is not supported", e.message)
    }
}

}
