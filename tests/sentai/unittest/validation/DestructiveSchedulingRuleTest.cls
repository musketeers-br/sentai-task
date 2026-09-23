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
    // Spec 004: additive to the availability errors for 04 and 05, never replaced by them.

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
    // (Since spec 004 the canonical flow has availability errors for 04/05 — not this rule.)
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        Do $$$AssertNotEquals(e.code, "DESTRUCTIVE_NOT_SCHEDULABLE")
    }

    // The manual-dispatch confirmation gate is unchanged (FR-017, SC-006): the typed
    // confirmation satisfies it ...
    Do $$$AssertTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, ..CanonicalConfirmations(), .pending))

    // ... and without it the destructive step is named as pending.
    Do $$$AssertNotTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, [], .pending))
    Do $$$AssertEquals(pending, "04")
}

Method TestNonDestructiveFlowPassesThisRule()
{
    Set id = ..CreateSupportedFlow("SchedRuleNonDestructive")
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Do $$$AssertTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))
}

}
