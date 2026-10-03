/// Spec 011 US3/US4: the demo seed, reset and status (sentai.demo.Demo). Every test works on flows
/// whose names carry a unique prefix (`Seed(prefix)`, `Reset(scope)`), so the dev instance's own
/// flows, including a real "Example: storage health check", are never touched; everything a test
/// creates is removed after it, and the demo marker is restored.
Class sentai.unittest.demo.DemoTest Extends sentai.unittest.SentaiTestCase
{

Property Prefix As %String;

Property MarkerBefore As %String;

Property LastResetBefore As %String;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Set ..Prefix = "demotest-"_$JOB_"-"_$I(^sentaiTestSeq)_" "
    Set ..MarkerBefore = $G(^sentai("config", "demo"))
    Set ..LastResetBefore = $G(^sentai("demo", "lastReset"))
    Quit sc
}

Method OnAfterOneTest() As %Status
{
    // Remove every flow this test created (by its prefix), with its runs.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID AS id FROM sentai_model.Flow WHERE name %STARTSWITH ?", ..Prefix)
    While rs.%Next() { Do ##class(sentai.demo.Demo).DeleteFlow(rs.%Get("id")) }
    If (..MarkerBefore = "") { Kill ^sentai("config", "demo") } Else { Set ^sentai("config", "demo") = ..MarkerBefore }
    If (..LastResetBefore = "") { Kill ^sentai("demo", "lastReset") } Else { Set ^sentai("demo", "lastReset") = ..LastResetBefore }
    Quit ##super()
}

/// The flow id of `name`, or "".
ClassMethod FlowId(name As %String) As %String
{
    Set id = ""
    Do ##class(sentai.model.Flow).NameIndexExists(name, .id)
    Quit id
}

ClassMethod Fixture(file As %String) As %DynamicObject
{
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile("/home/irisowner/dev/tests/fixtures/"_file)
    Quit ##class(%DynamicAbstractObject).%FromJSON(stream)
}

/// Setup without its explicit confirmation does nothing on a normal installation.
Method TestSetupRefusesWithoutConfirmation()
{
    Kill ^sentai("config", "demo")
    Set out = ##class(sentai.demo.Demo).Setup(0)
    Do $$$AssertEquals(out.ok, 0)
    Do $$$AssertEquals($D(^sentai("config", "demo")), 0, "no marker written")
    Do $$$AssertTrue(out.problems.%Size() > 0)
}

/// The shipped definitions equal the shared fixtures (the canvas and the spec 014 recorder read
/// the same files).
Method TestExampleMatchesFixture()
{
    Set def = ##class(sentai.demo.Demo).ExampleDefinition()
    Set fixture = ..Fixture("example-flow.json")
    Do $$$AssertEquals(##class(sentai.demo.Demo).Fingerprint(def), ##class(sentai.demo.Demo).Fingerprint(fixture))
    Do $$$AssertEquals(def.name, fixture.name)
    Do $$$AssertEquals(def.canvasGeometry.%ToJSON(), fixture.canvasGeometry.%ToJSON())
}

Method TestShowcaseMatchesFixture()
{
    Set def = ##class(sentai.demo.Demo).ShowcaseDefinition()
    Set fixture = ..Fixture("showcase-flow.json")
    Do $$$AssertEquals(##class(sentai.demo.Demo).Fingerprint(def), ##class(sentai.demo.Demo).Fingerprint(fixture))
    Do $$$AssertEquals(def.name, fixture.name)
    Do $$$AssertEquals(def.canvasGeometry.%ToJSON(), fixture.canvasGeometry.%ToJSON())
}

/// Spec 022 (research R-2): the weekly window — the third definition shared with the canvas —
/// completes the two-sided fixture sync; the gallery card's bundled definition is compared with
/// the same fixture by vitest (frontend/src/lib/flows/runbooks.test.ts), so neither can drift.
Method TestWeeklyWindowMatchesFixture()
{
    Set def = ##class(sentai.demo.DemoFlows).Payload()
    Set fixture = ..Fixture("weekly-window-flow.json")
    Do $$$AssertEquals(##class(sentai.demo.Demo).Fingerprint(def), ##class(sentai.demo.Demo).Fingerprint(fixture))
    Do $$$AssertEquals(def.name, fixture.name)
    Do $$$AssertEquals(def.canvasGeometry.%ToJSON(), fixture.canvasGeometry.%ToJSON())
}

/// Data-model §5: three parallel integrity checks (one on iris-target) → ALL_MUST_SUCCEED join →
/// db-size-report; validates with no errors against a registered target.
Method TestSeedCreatesShowcase()
{
    Set out = ##class(sentai.demo.Demo).Seed(..Prefix)
    Do $$$AssertEquals(out.ok, 1, out.%ToJSON())
    Set id = ..FlowId(..Prefix_##class(sentai.demo.Demo).#SHOWCASENAME)
    Do $$$AssertNotEquals(id, "")
    Do $$$AssertNotEquals(..FlowId(..Prefix_##class(sentai.demo.Demo).#EXAMPLENAME), "")

    Set shape = ##class(sentai.rest.Dispatcher).ShapeFlow(##class(sentai.model.Flow).%OpenId(id, 0), 1)
    Do $$$AssertEquals(shape.steps.%Size(), 4)
    Do $$$AssertEquals(shape.edges.%Size(), 3)
    Do $$$AssertEquals(shape.joins.%Size(), 1)
    Do $$$AssertEquals(shape.joins.%Get(0).policy, "ALL_MUST_SUCCEED")
    Set remote = 0, types = ""
    Set it = shape.steps.%GetIterator()
    While it.%GetNext(.k, .s) {
        Set types = types_s.type_","
        Set:(s.target = "iris-target") remote = remote + 1
        Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive(s.type), 0, s.type_" is non-destructive")
        Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable(s.type), 1, s.type_" is available")
    }
    Do $$$AssertEquals(remote, 1, "one step on iris-target")

    // Validation with the target registered (the double answers the target's reads).
    Do ##class(sentai.demo.Demo).EnsureTarget()
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertEquals(report.errors.%Size(), 0, report.%ToJSON())
}

/// A second Seed changes neither the id nor the revision of an intact flow.
Method TestSeedIsIdempotent()
{
    Do ##class(sentai.demo.Demo).Seed(..Prefix)
    Set name = ..Prefix_##class(sentai.demo.Demo).#SHOWCASENAME
    Set id = ..FlowId(name), rev = ##class(sentai.model.Flow).%OpenId(id, 0).revision
    Set out = ##class(sentai.demo.Demo).Seed(..Prefix)
    Do $$$AssertEquals(out.ok, 1)
    Do $$$AssertEquals(..FlowId(name), id)
    Do $$$AssertEquals(##class(sentai.model.Flow).%OpenId(id, 0).revision, rev)
}

/// A changed showcase (a visitor removed step 04) is restored as shipped, keeping its id.
Method TestSeedRepairsChangedShowcase()
{
    Do ##class(sentai.demo.Demo).Seed(..Prefix)
    Set name = ..Prefix_##class(sentai.demo.Demo).#SHOWCASENAME
    Set id = ..FlowId(name)
    Set changed = ##class(sentai.demo.Demo).ShowcaseDefinition()
    Do changed.%Set("name", name)
    Do changed.steps.%Remove(3)
    Set changed.edges = [], changed.joins = []
    Set rev = ##class(sentai.model.Flow).%OpenId(id, 0).revision
    $$$ThrowOnError(##class(sentai.model.Flow).SaveGraph(changed, id, rev, "visitor", .id))

    Set out = ##class(sentai.demo.Demo).Seed(..Prefix)
    Do $$$AssertEquals(out.ok, 1)
    Do $$$AssertEquals(..FlowId(name), id)
    Set shape = ##class(sentai.rest.Dispatcher).ShapeFlow(##class(sentai.model.Flow).%OpenId(id, 0), 1)
    Do $$$AssertEquals(shape.steps.%Size(), 4)
    Do $$$AssertEquals(shape.joins.%Size(), 1)
}

/// A visitor flow with a run, a step run and a log entry, named inside this test's scope.
Method VisitorFlowWithRun(label As %String) As %String
{
    Set payload = ##class(sentai.demo.Demo).ExampleDefinition()
    Do payload.%Set("name", ..Prefix_"visitor "_label)
    Do payload.%Remove("canvasGeometry")
    $$$ThrowOnError(##class(sentai.model.Flow).SaveGraph(payload, "", 0, "visitor", .id))
    Set run = ##class(sentai.dispatch.WaveDispatcher).CreateRun(id, [], "visitor", .code, .detail)
    Do $$$AssertTrue($IsObject(run), "run created "_$G(code)_" "_$G(detail))
    Set runId = ##class(sentai.model.Run).GuidIndexOpen(run.guid, 0).%Id()
    $$$ThrowOnError(##class(sentai.model.LogEntry).Append(runId, "01", "info", "visitor run"))
    Quit id
}

/// Reset refuses on an instance that is not marked as a demo.
Method TestResetRefusesWithoutMarker()
{
    Kill ^sentai("config", "demo")
    Set id = ..VisitorFlowWithRun("kept")
    Set out = ##class(sentai.demo.Demo).Reset(..Prefix)
    Do $$$AssertEquals(out.ok, 0)
    Do $$$AssertTrue(##class(sentai.model.Flow).%ExistsId(id), "nothing removed")
}

/// Visitor flows go with their runs, step runs and log entries; the seeded flows stay with theirs.
Method TestResetRemovesVisitorFlows()
{
    Set ^sentai("config", "demo") = 1
    Do ##class(sentai.demo.Demo).Seed(..Prefix)
    Set a = ..VisitorFlowWithRun("a"), b = ..VisitorFlowWithRun("b")
    Set showcase = ..FlowId(..Prefix_##class(sentai.demo.Demo).#SHOWCASENAME)
    Set run = ##class(sentai.dispatch.WaveDispatcher).CreateRun(showcase, [], "visitor", .code, .detail)
    Set keptRun = ##class(sentai.model.Run).GuidIndexOpen(run.guid, 0).%Id()

    Set out = ##class(sentai.demo.Demo).Reset(..Prefix)
    Do $$$AssertEquals(out.ok, 1, out.%ToJSON())
    For id = a, b {
        Do $$$AssertNotTrue(##class(sentai.model.Flow).%ExistsId(id), "visitor flow "_id_" removed")
        &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Run WHERE flow = :id)
        Do $$$AssertEquals(n, 0, "its runs removed")
    }
    &sql(SELECT COUNT(*) INTO :orphans FROM sentai_model.LogEntry WHERE run NOT IN (SELECT ID FROM sentai_model.Run))
    Do $$$AssertEquals(orphans, 0, "no orphan log entries")
    Do $$$AssertTrue(##class(sentai.model.Flow).%ExistsId(showcase), "showcase kept")
    Do $$$AssertTrue(##class(sentai.model.Run).%ExistsId(keptRun), "showcase run kept")
    Do $$$AssertNotEquals(..FlowId(..Prefix_##class(sentai.demo.Demo).#EXAMPLENAME), "", "example kept")
}

/// FR-012: nothing but the listed items changes.
Method TestResetLeavesSettingsAlone()
{
    Set ^sentai("config", "demo") = 1
    Set insecure = $G(^sentai("config", "allowInsecureTargets"))
    Do ##class(sentai.demo.Demo).EnsureTarget()
    Set before = ##class(sentai.model.Target).NameIndexOpen("iris-target", 0).baseUrl
    Do ##class(sentai.demo.Demo).Reset(..Prefix)
    Do $$$AssertEquals($G(^sentai("config", "allowInsecureTargets")), insecure)
    Do $$$AssertEquals(##class(sentai.model.Target).NameIndexOpen("iris-target", 0).baseUrl, before)
    Do $$$AssertEquals(##class(sentai.model.Target).NameIndexOpen("iris-target", 0).online, 1)
}

Method TestResetRecordsLastReset()
{
    Set ^sentai("config", "demo") = 1
    Do ..VisitorFlowWithRun("r")
    Set out = ##class(sentai.demo.Demo).Reset(..Prefix)
    Set rec = $G(^sentai("demo", "lastReset"))
    Do $$$AssertEquals($LG(rec, 2), "ok")
    Do $$$AssertTrue($LG(rec, 1) '= "", "time recorded")
    Do $$$AssertTrue($LG(rec, 3) [ "1 flow", $LG(rec, 3))
}

/// Data-model §4.
Method TestStatusShape()
{
    Set ^sentai("config", "demo") = 1
    Do ##class(sentai.demo.Demo).Seed(..Prefix)
    Do ..VisitorFlowWithRun("s")
    Set st = ##class(sentai.demo.Demo).Status(..Prefix)
    Do $$$AssertEquals(st.demo, 1)
    Do $$$AssertEquals(st.flows, 3)
    Do $$$AssertEquals(st.visitorFlows, 1)
    Do $$$AssertEquals(st.visitorRuns, 1)
    Do $$$AssertEquals(st.runs, 0, "runs of the seeded flows only (data-model §4)")
    Do $$$AssertTrue(st.%IsDefined("lastReset"))
}

/// A visitor flow with a join goes too (the table name "Join" is an SQL reserved word).
Method TestResetRemovesAFlowWithAJoin()
{
    Set ^sentai("config", "demo") = 1
    Set payload = ##class(sentai.demo.Demo).ShowcaseDefinition()
    Do payload.%Set("name", ..Prefix_"visitor with join")
    $$$ThrowOnError(##class(sentai.model.Flow).SaveGraph(payload, "", 0, "visitor", .id))
    Set out = ##class(sentai.demo.Demo).Reset(..Prefix)
    Do $$$AssertEquals(out.ok, 1, out.%ToJSON())
    Do $$$AssertNotTrue(##class(sentai.model.Flow).%ExistsId(id), "removed")
    &sql(SELECT COUNT(*) INTO :joins FROM sentai_model."Join" WHERE flow = :id)
    Do $$$AssertEquals(joins, 0)
}

}
