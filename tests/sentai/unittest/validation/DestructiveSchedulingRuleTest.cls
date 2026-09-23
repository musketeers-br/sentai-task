/// Scheduling of any flow containing a destructive step is out of scope in v1 (spec.md Change
/// Log 2026-09-22). The refusal is scoped to /schedule only: the same flow stays valid for
/// /validate and for manual /dispatch with typed confirmation (FR-017, SC-006).
Class sentai.unittest.validation.DestructiveSchedulingRuleTest Extends sentai.unittest.SentaiTestCase
{

Method TestDestructiveStepIsAnErrorForScheduleNeverAWarning()
{
    Set id = ..CreateCanonicalFlow("SchedRuleDestructive")
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)

    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "DESTRUCTIVE_NOT_SCHEDULABLE") && (e.stepId = "04") Set found = 1
        // Only the destructive step is named — the non-destructive ones are not.
        If (e.code = "DESTRUCTIVE_NOT_SCHEDULABLE") Do $$$AssertEquals(e.stepId, "04")
    }
    Do $$$AssertTrue(found)
    Do $$$AssertNotTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))

    Set foundAsWarning = 0
    Set iter2 = report."warnings".%GetIterator()
    While iter2.%GetNext(.k, .w) {
        If (w.code = "DESTRUCTIVE_NOT_SCHEDULABLE") Set foundAsWarning = 1
    }
    Do $$$AssertNotTrue(foundAsWarning)
}

Method TestDestructiveStepDoesNotAffectValidateOrManualDispatch()
{
    Set id = ..CreateCanonicalFlow("SchedRuleDispatchUnaffected")

    // /validate and /dispatch share Validate(): the scheduling-only rule never appears there.
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))

    // Manual dispatch with the typed confirmation still succeeds (FR-017) ...
    Set errorCode = "", errorDetail = "", vr = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, ..CanonicalConfirmations(), "tester", .errorCode, .errorDetail, .vr)
    Do $$$AssertEquals(errorCode, "")
    Do $$$AssertTrue($IsObject(run))

    // ... and without it is still refused, naming the destructive step (SC-006 unchanged).
    Set run2 = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .errorCode, .errorDetail, .vr)
    Do $$$AssertEquals(errorCode, "CONFIRMATION_REQUIRED")
    Do $$$AssertEquals(errorDetail, "04")
}

Method TestNonDestructiveFlowPassesThisRule()
{
    Set sc = ##class(sentai.model.Flow).SaveGraph(..NonDestructiveFlowPayload("SchedRuleNonDestructive"), "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Do $$$AssertTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))
}

}
