/// The seeded use-case flow (sentai.demo.DemoFlows, docs/use-case-weekly-maintenance.md):
/// the seed creates exactly the document's graph, seeding twice never duplicates or
/// clobbers, the payload only names catalog types that are available, and the seeded flow
/// validates clean through the one gate. Every test seeds under a unique name and removes
/// it after, so the operator's own "Weekly maintenance window" (installed by the image
/// build) is never touched.
Class sentai.unittest.demo.DemoFlowsTest Extends sentai.unittest.SentaiTestCase
{

/// A unique name per call, the same way every fixture in this suite avoids the flow name's
/// unique index (SentaiTestCase.CanonicalFlowPayload).
ClassMethod UniqueName(prefix As %String = "DemoSeed") As %String
{
    Quit prefix_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)
}

Method TestSeedsTheUseCaseGraph()
{
    Set name = ..UniqueName()
    Set flowId = ##class(sentai.demo.DemoFlows).EnsureSeeded(name)
    Do $$$AssertTrue(flowId '= "", "EnsureSeeded returned a flow id")

    // The document's step types, in step id order.
    Set types = ""
    &sql(DECLARE c CURSOR FOR SELECT type INTO :t FROM sentai_model.Step WHERE flow = :flowId ORDER BY id)
    &sql(OPEN c)
    For { &sql(FETCH c) Quit:SQLCODE  Set types = types_$S(types = "":"", 1:",")_t }
    &sql(CLOSE c)
    Do $$$AssertEquals(types, "storage-headroom-check,db-size-report,switch-journal,integrity-check,integrity-check,purge-task-history")

    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Edge WHERE flow = :flowId)
    Do $$$AssertEquals(+n, 6, "six edges (fan-in at 03 and 06)")
    Set n = 0
    // "Join" is a reserved word: the table only reads under a delimited identifier.
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model."Join" WHERE flow = :flowId)
    Do $$$AssertEquals(+n, 2, "one join per fan-in")

    // Declared parameters survive the save.
    &sql(SELECT %ID INTO :sid FROM sentai_model.Step WHERE flow = :flowId AND id = '01')
    Set headroom = ##class(sentai.model.Step).%OpenId(sid, 0)
    Do $$$AssertTrue($IsObject(headroom) && ($IsObject(headroom.parameters) && (headroom.parameters.minFreePercent = 15)), "step 01 keeps minFreePercent")
    &sql(SELECT %ID INTO :sid FROM sentai_model.Step WHERE flow = :flowId AND id = '06')
    Set purge = ##class(sentai.model.Step).%OpenId(sid, 0)
    Do $$$AssertTrue($IsObject(purge) && ($IsObject(purge.parameters) && (purge.parameters.keepDays = 30)), "step 06 keeps keepDays")

    Do ##class(sentai.demo.DemoFlows).Remove(name)
    Do $$$AssertTrue('##class(sentai.model.Flow).NameIndexExists(name, .gone), "Remove deletes the flow")
}

Method TestSeedingTwiceReturnsTheSameFlow()
{
    Set name = ..UniqueName("DemoSeedTwice")
    Set id1 = ##class(sentai.demo.DemoFlows).EnsureSeeded(name)
    Do $$$AssertTrue(id1 '= "", "the first seed created the flow")

    Set id2 = ##class(sentai.demo.DemoFlows).EnsureSeeded(name)
    Do $$$AssertEquals(id2, id1, "the second seed returns the existing flow")

    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Flow WHERE name = :name)
    Do $$$AssertEquals(+n, 1, "exactly one flow of that name")

    // The second seed returned early: the first was not rewritten (SaveGraph would have
    // bumped the revision).
    Set flow = ##class(sentai.model.Flow).%OpenId(id1, 0)
    Do $$$AssertTrue($IsObject(flow) && (flow.revision = 1), "an existing flow is never overwritten")
    Do $$$AssertTrue($IsObject(flow) && (flow.savedBy = "sentai.demo"), "the seed records savedBy")

    Do ##class(sentai.demo.DemoFlows).Remove(name)
}

/// Guards the payload against the catalog's future: if a step type ever becomes
/// unavailable, this fails before the document and the seed can drift apart.
Method TestPayloadNamesOnlyAvailableCatalogTypes()
{
    Set payload = ##class(sentai.demo.DemoFlows).Payload()
    Do $$$AssertEquals(payload.name, "Weekly maintenance window", "the payload is the document's flow")
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .step) {
        Do $$$AssertTrue(##class(sentai.registry.StepType).IsAvailable(step.type), "catalog type "_step.type_" is available")
    }
}

/// The seeded flow passes the one gate clean — the promise the document makes about the
/// "Weekly maintenance window" on any instance (USER and %SYS exist everywhere, Default is
/// a built-in WQM category). The double answers the category read (SentaiTestCase
/// OnBeforeOneTest); namespaces are read for real.
Method TestSeededFlowValidatesClean()
{
    Set name = ..UniqueName("DemoSeedValid")
    Set flowId = ##class(sentai.demo.DemoFlows).EnsureSeeded(name)
    Do $$$AssertTrue(flowId '= "", "the seed created the flow")

    Set report = ##class(sentai.validation.FlowValidator).Validate(flowId, "fake-token")
    Do $$$AssertEquals(report.errors.%Size(), 0, "no validation errors")
    Do $$$AssertEquals(report.warnings.%Size(), 0, "no validation warnings")

    Do ##class(sentai.demo.DemoFlows).Remove(name)
}

}
