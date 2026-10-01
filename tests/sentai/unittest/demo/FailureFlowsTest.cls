/// The two seeded failure demos (sentai.demo.FailureFlows, docs/use-case-failure-demos.md):
/// each seed creates exactly the documented graph, seeding twice never duplicates or
/// clobbers, both payloads name only catalog types that are available and non-destructive
/// (so both demos dispatch with no typed confirmation — the failure, not a gate, is the
/// show), both pass the one gate clean, the failing steps really fail — the headroom check
/// against this machine's real disks, the posture report over scripted platform answers —
/// and the failing-check graph cascades through the real eligibility computation: 03 and 04
/// end "failed" on "One or more required inputs failed", never a success (Constitution IV).
/// Every test seeds under a unique name and removes it after, so the operator's own copies
/// (installed by the image build) are never touched.
Class sentai.unittest.demo.FailureFlowsTest Extends sentai.unittest.SentaiTestCase
{

/// A unique name per call, the same way DemoFlowsTest avoids the flow name's unique index.
ClassMethod UniqueName(prefix As %String = "FailureDemo") As %String
{
    Quit prefix_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)
}

/// The `parameters` of the step with id `stepId` in `def`, "" when it declares none.
ClassMethod ParametersOf(def As %DynamicObject, stepId As %String) As %DynamicObject
{
    Set found = ""
    Set iter = def."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (s.id = stepId) Set found = $S($IsObject(s.parameters):s.parameters, 1:"")
    }
    Quit found
}

Method TestFailingCheckSeedsTheDocumentedGraph()
{
    Set name = ..UniqueName("FailureCascade")
    Set flowId = ##class(sentai.demo.FailureFlows).EnsureSeeded("failing-check", name)
    Do $$$AssertTrue(flowId '= "", "EnsureSeeded returned a flow id")

    // The document's step types, in step id order.
    Set types = ""
    &sql(DECLARE c CURSOR FOR SELECT type INTO :t FROM sentai_model.Step WHERE flow = :flowId ORDER BY id)
    &sql(OPEN c)
    For { &sql(FETCH c) Quit:SQLCODE  Set types = types_$S(types = "":"", 1:",")_t }
    &sql(CLOSE c)
    Do $$$AssertEquals(types, "storage-headroom-check,db-size-report,switch-journal,integrity-check")

    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Edge WHERE flow = :flowId)
    Do $$$AssertEquals(+n, 3, "two sources into 03, then 03 to 04")
    Set n = 0
    // "Join" is a reserved word: the table only reads under a delimited identifier.
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model."Join" WHERE flow = :flowId)
    Do $$$AssertEquals(+n, 1, "the fan-in at 03 is the only join")
    Set p = ""
    &sql(SELECT policy INTO :p FROM sentai_model."Join" WHERE flow = :flowId AND target = '03')
    Do $$$AssertEquals(p, "ALL_MUST_SUCCEED")

    // The demo's one data trick: a threshold no location can ever satisfy.
    &sql(SELECT %ID INTO :sid FROM sentai_model.Step WHERE flow = :flowId AND id = '01')
    Set headroom = ##class(sentai.model.Step).%OpenId(sid, 0)
    Do $$$AssertTrue($IsObject(headroom) && ($IsObject(headroom.parameters) && (headroom.parameters.minFreePercent = 100)), "step 01 keeps minFreePercent = 100")

    Do ##class(sentai.demo.FailureFlows).Remove(name)
    Do $$$AssertTrue('##class(sentai.model.Flow).NameIndexExists(name, .gone), "Remove deletes the flow")
}

Method TestSecurityPostureSeedsTheDocumentedGraph()
{
    Set name = ..UniqueName("FailurePosture")
    Set flowId = ##class(sentai.demo.FailureFlows).EnsureSeeded("security-posture", name)
    Do $$$AssertTrue(flowId '= "", "EnsureSeeded returned a flow id")

    Set types = ""
    &sql(DECLARE c CURSOR FOR SELECT type INTO :t FROM sentai_model.Step WHERE flow = :flowId ORDER BY id)
    &sql(OPEN c)
    For { &sql(FETCH c) Quit:SQLCODE  Set types = types_$S(types = "":"", 1:",")_t }
    &sql(CLOSE c)
    Do $$$AssertEquals(types, "security-posture-report")

    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Edge WHERE flow = :flowId)
    Do $$$AssertEquals(+n, 0, "a single step, no edges")
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model."Join" WHERE flow = :flowId)
    Do $$$AssertEquals(+n, 0, "no joins")

    &sql(SELECT %ID INTO :sid FROM sentai_model.Step WHERE flow = :flowId AND id = '01')
    Set posture = ##class(sentai.model.Step).%OpenId(sid, 0)
    Do $$$AssertTrue($IsObject(posture) && ($IsObject(posture.parameters) && (posture.parameters.failOnFindings = 1)), "step 01 keeps failOnFindings")

    Do ##class(sentai.demo.FailureFlows).Remove(name)
    Do $$$AssertTrue('##class(sentai.model.Flow).NameIndexExists(name, .gone), "Remove deletes the flow")
}

Method TestSeedingTwiceReturnsTheSameFlow()
{
    For demo = "failing-check", "security-posture" {
        Set name = ..UniqueName("FailureTwice")
        Set id1 = ##class(sentai.demo.FailureFlows).EnsureSeeded(demo, name)
        Do $$$AssertTrue(id1 '= "", "the first seed created the flow")

        Set id2 = ##class(sentai.demo.FailureFlows).EnsureSeeded(demo, name)
        Do $$$AssertEquals(id2, id1, "the second seed returns the existing flow")

        Set n = 0
        &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Flow WHERE name = :name)
        Do $$$AssertEquals(+n, 1, "exactly one flow of that name")

        // The second seed returned early: the first was not rewritten (SaveGraph would have
        // bumped the revision).
        Set flow = ##class(sentai.model.Flow).%OpenId(id1, 0)
        Do $$$AssertTrue($IsObject(flow) && (flow.revision = 1), "an existing flow is never overwritten")
        Do $$$AssertTrue($IsObject(flow) && (flow.savedBy = "sentai.demo"), "the seed records savedBy")

        Do ##class(sentai.demo.FailureFlows).Remove(name)
    }
}

/// Guards the payloads against the catalog's future: the demos must stay dispatchable on a
/// fresh stack with no typed confirmation — every type available, none destructive — and the
/// documented failures must be the payloads' own data, nothing the seed adds in code.
Method TestPayloadsNameOnlyAvailableNonDestructiveTypes()
{
    Set def = ##class(sentai.demo.FailureFlows).Definition("failing-check")
    Do $$$AssertTrue($IsObject(def), "the failing-check definition exists")
    Set iter = def."steps".%GetIterator()
    While iter.%GetNext(.k, .step) {
        Do $$$AssertTrue(##class(sentai.registry.StepType).IsAvailable(step.type), "catalog type "_step.type_" is available")
        Do $$$AssertNotTrue(##class(sentai.registry.StepType).IsDestructive(step.type), "catalog type "_step.type_" is not destructive")
    }
    Set params = ..ParametersOf(def, "01")
    Do $$$AssertTrue($IsObject(params) && (params.minFreePercent = 100), "an impossible threshold")

    Set def = ##class(sentai.demo.FailureFlows).Definition("security-posture")
    Do $$$AssertTrue($IsObject(def), "the security-posture definition exists")
    Set iter = def."steps".%GetIterator()
    While iter.%GetNext(.k, .step) {
        Do $$$AssertTrue(##class(sentai.registry.StepType).IsAvailable(step.type), "catalog type "_step.type_" is available")
        Do $$$AssertNotTrue(##class(sentai.registry.StepType).IsDestructive(step.type), "catalog type "_step.type_" is not destructive")
    }
    Set params = ..ParametersOf(def, "01")
    Do $$$AssertTrue($IsObject(params) && (params.failOnFindings = 1), "fail the step on any high finding")

    // An unknown key names no demo at all — the closed set stays closed.
    Do $$$AssertEquals(##class(sentai.demo.FailureFlows).Definition("no-such-demo"), "", "unknown key: no definition")
    Do $$$AssertEquals(##class(sentai.demo.FailureFlows).EnsureSeeded("no-such-demo"), "", "unknown key: nothing seeded")
}

/// Both demos pass the one gate clean — the same promise DemoFlowsTest makes for the weekly
/// flow (USER and %SYS exist everywhere, Default is a built-in WQM category). The double
/// answers the category read (SentaiTestCase OnBeforeOneTest); namespaces are read for real.
Method TestSeededFlowsValidateClean()
{
    For demo = "failing-check", "security-posture" {
        Set name = ..UniqueName("FailureValid")
        Set flowId = ##class(sentai.demo.FailureFlows).EnsureSeeded(demo, name)
        Do $$$AssertTrue(flowId '= "", "the seed created the flow")

        Set report = ##class(sentai.validation.FlowValidator).Validate(flowId, "fake-token")
        Do $$$AssertEquals(report.errors.%Size(), 0, "no validation errors")
        Do $$$AssertEquals(report.warnings.%Size(), 0, "no validation warnings")

        Do ##class(sentai.demo.FailureFlows).Remove(name)
    }
}

/// The demo's failure is the platform's real answer, not a fixture: dispatch builds the task
/// exactly this way (InProcessExecutor.NewTask reads the catalog and applies the declared
/// schema only), so with the payload's own parameters the check really runs against every
/// database and journal location of the machine the suite runs on — and no location is ever
/// 100% free, which is what makes the demo deterministic.
Method TestFailingCheckStepReallyFailsOnThisMachine()
{
    Set params = ..ParametersOf(##class(sentai.demo.FailureFlows).Definition("failing-check"), "01")
    Do $$$AssertStatusOK(##class(sentai.dispatch.InProcessExecutor).NewTask("storage-headroom-check", params, .task))
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(task, .outcome)
    Do $$$AssertEquals(outcome("ok"), 0, "a 100% threshold no location can satisfy")
    Do $$$AssertTrue(outcome("reason") [ "Storage headroom below 100%", outcome("reason"))
    Do $$$AssertTrue(outcome("reason") [ "below the 100% threshold", outcome("reason"))
    Set result = {}.%FromJSON(outcome("result"))
    Do $$$AssertTrue(result.locations.%Size() > 0, "the report is kept on failure")
}

/// Same honesty for the posture report, over the scripted platform answers ReportSecurityTest
/// uses (audit on, one %All holder): the demo's own failOnFindings turns the report into the
/// step's failure — the platform's text, verbatim.
Method TestPostureStepReallyFailsOnFindings()
{
    Do ..ScriptSecurity(1)
    Set params = ..ParametersOf(##class(sentai.demo.FailureFlows).Definition("security-posture"), "01")
    Set sc = ##class(sentai.dispatch.ReadExecutor).Build("security-posture-report", params, ##class(sentai.steps.reports.Reader).For("", "tok"), .report)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "1 high finding: ALL_ROLE_HOLDER _SYSTEM", $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertTrue($IsObject(report) && (report.findings.%Size() > 0), "the report is kept")
}

/// The documented cascade, through the engine that will run it: a failed input and a
/// completed sibling make the ALL_MUST_SUCCEED target fail with the contracted text, and the
/// failure keeps propagating — 04 fails the same way and nothing is left to run, so
/// FinalizeRun can only answer "failed" (Constitution IV).
Method TestFailingCheckCascadesThroughTheRealEligibility()
{
    Set name = ..UniqueName("FailureCascadeRun")
    Set flowId = ##class(sentai.demo.FailureFlows).EnsureSeeded("failing-check", name)
    Do $$$AssertTrue(flowId '= "", "the seed created the flow")
    Set run = ..DispatchUngated(flowId)

    Set sr01 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "01", 4)
    Set sr02 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "02", 4)
    Do sr01.TransitionTo("failed", "Storage headroom below 100%: demo")
    Do sr02.TransitionTo("completed")

    Do ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailed, .eligible)
    Do $$$AssertTrue(anyFailed, "the join failure is reported")
    Set sr03 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "03", 0)
    Do $$$AssertEquals(sr03.state, "failed", "the join target never runs")
    Do $$$AssertEquals(sr03.failureReason, "One or more required inputs failed")

    Do ##class(sentai.dispatch.WaveDispatcher).ComputeEligibleSteps(run.guid, .anyFailedAgain, .eligibleAgain)
    Set sr04 = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), "04", 0)
    Do $$$AssertEquals(sr04.state, "failed", "the failure keeps propagating downstream")
    Do $$$AssertEquals(sr04.failureReason, "One or more required inputs failed")

    // The runs belong to this test; Remove refuses a flow that still has them.
    Do ##class(sentai.unittest.SentaiTestCase).RemoveRunsAfter(..RunIdBefore)
    Do ##class(sentai.demo.FailureFlows).Remove(name)
    Do $$$AssertTrue('##class(sentai.model.Flow).NameIndexExists(name, .gone), "Remove deletes the flow")
}

// --- scripted platform answers for the posture report (the ReportSecurityTest fixtures) ---

ClassMethod Ok(result) As %String
{
    Quit {"status": {"errors": [], "summary": ""}, "console": [], "result": (result)}.%ToJSON()
}

ClassMethod Script(path As %String, result, status As %Integer = 200)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(path, "GET", status, "", $S(status = 200:..Ok(result), 1:"{""status"":{""summary"":"""_result_"""}}"))
}

/// Users and roles, services and audit, as IRIS 2026.2 answers them (ReportSecurityTest).
Method ScriptSecurity(auditOn As %Boolean = 1)
{
    Do ..Script("/api/admin/v2/security/users", [
        {"Name": "_SYSTEM", "FullName": "SQL System Manager", "Enabled": true},
        {"Name": "ops", "FullName": "Operator", "Enabled": true},
        {"Name": "IAM", "FullName": "IAM user", "Enabled": false}])
    Do ..Script("/api/admin/v2/security/user?name=_SYSTEM", {"Enabled": true, "Roles": ["%All"], "Password": "must-not-leak", "PasswordHash": "must-not-leak", "AccountNeverExpires": true, "PasswordNeverExpires": false})
    Do ..Script("/api/admin/v2/security/user?name=ops", {"Enabled": true, "Roles": ["%Operator"], "AccountNeverExpires": false, "PasswordNeverExpires": false})
    Do ..Script("/api/admin/v2/security/services", [
        {"Name": "%Service_Login", "Enabled": true, "AuthenticationMethods": ["Password"]},
        {"Name": "%Service_Weblink", "Enabled": false, "AuthenticationMethods": ["Unauthenticated"]}])
    Set audit = {}
    Do audit.%Set("Enabled", auditOn, "boolean")
    Do ..Script("/api/admin/v2/security/audit/enabled", audit)
}

}
