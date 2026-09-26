/// Spec 006 T002/T003 — destructiveness from the step-type catalog (data-model §Destructiveness)
/// and the SentaiTask origin (FR-005).
Class sentai.unittest.catalog.TaskOriginDestructiveTest Extends sentai.unittest.SentaiTestCase
{

/// A task built from reads that name `taskClass` (or a failed single read when "").
ClassMethod Shape(taskClass As %String, name As %String = "Some task", singleStatus As %Integer = 200) As %DynamicObject
{
    Set single = ##class(sentai.unittest.catalog.CatalogFixtures).Read(singleStatus, $S(singleStatus = 200:{"TaskClass": (taskClass), "RunAsUser": "_SYSTEM", "TimePeriod": "Daily"}, 1:""))
    Set info = ##class(sentai.unittest.catalog.CatalogFixtures).Read(200, ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult())
    Quit ##class(sentai.catalog.TaskShape).Build(9, ##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(9, name), single, info)
}

// --- T002: rules 1, 2, 4 ---

Method TestCatalogDestructiveClassIsKnownDestructive()
{
    Set t = ..Shape("%SYS.Task.PurgeTaskHistory")
    Do $$$AssertTrue(t.destructive)
    Do $$$AssertNotTrue(t.destructiveUnknown)
    Do $$$AssertTrue(t.isDestructive)
}

Method TestAuditPurgeIsDestructiveAfterD4()
{
    Set t = ..Shape("%SYS.Task.PurgeAudit", "Purge Audit Database")
    Do $$$AssertTrue(t.destructive)
    Do $$$AssertNotTrue(t.destructiveUnknown)
}

Method TestUnknownOrUnavailableClassIsUnknown()
{
    Set t = ..Shape("%SYS.Task.SecurityScan")
    Do $$$AssertNotTrue(t.destructive)
    Do $$$AssertTrue(t.destructiveUnknown)
    Set t = ..Shape("", "Gone", 404)
    Do $$$AssertNotTrue(t.destructive)
    Do $$$AssertTrue(t.destructiveUnknown)
    Set t = ..Shape("%SYS.Task.IntegrityCheck")
    Do $$$AssertNotTrue(t.destructive)
    Do $$$AssertNotTrue(t.destructiveUnknown, "a known non-destructive class is known")
}

// --- T003: SentaiTask origin and rule 3 ---

/// Removes a flow and its graph (the relationship refuses deleting a flow with children).
ClassMethod DeleteFlowGraph(flowId As %String)
{
    &sql(DELETE FROM sentai_model.Edge WHERE flow = :flowId)
    &sql(DELETE FROM sentai_model."Join" WHERE flow = :flowId)
    &sql(DELETE FROM sentai_model.Step WHERE flow = :flowId)
    Do ##class(sentai.model.Flow).%DeleteId(flowId)
}

Method TestGeneratorNamesParse()
{
    For case = $LB("SentaiTask: 1#01", "1", "01"), $LB("SentaiTask: 12#a1", "12", "a1"), $LB("SentaiTask: 3#7", "3", "7") {
        Do $$$AssertTrue(##class(sentai.catalog.TaskOrigin).Parse($LG(case, 1), .flowId, .stepId), $LG(case, 1))
        Do $$$AssertEquals(flowId, $LG(case, 2))
        Do $$$AssertEquals(stepId, $LG(case, 3))
    }
}

Method TestNearMissesHaveNoOrigin()
{
    For name = "SentaiTask: 1#01 copy", "SentaiTask:1#01", "sentaitask: 1#01", "SentaiTask: 01#01", "SentaiTask: 1#", "SentaiTask: 1#123456789", "SentaiTaskX: 1#01", "SentaiTask: 1#0 1", " SentaiTask: 1#01" {
        Do $$$AssertNotTrue(##class(sentai.catalog.TaskOrigin).Parse(name, .f, .s), name)
        Set t = ..Shape("%SYS.Task.IntegrityCheck", name)
        Do $$$AssertNotTrue(t.%IsDefined("origin"), name)
    }
}

Method TestOriginOfAnExistingFlow()
{
    Set flowId = ..CreateSupportedFlow("Origin")
    Set t = ..Shape("sentai.dispatch.ScheduledFlowTask", "SentaiTask: "_flowId_"#02")
    Do $$$AssertEquals(t.origin.flowId, flowId)
    Do $$$AssertEquals(t.origin.%GetTypeOf("flowId"), "string")
    Do $$$AssertEquals(t.origin.stepId, "02")
    Do $$$AssertEquals(t.origin.%GetTypeOf("flowExists"), "boolean")
    Do $$$AssertTrue(t.origin.flowExists)
    Do ..DeleteFlowGraph(flowId)
}

Method TestDeletedFlowKeepsOriginFlaggedNotFound()
{
    Set flowId = ..CreateSupportedFlow("OriginGone")
    Do ..DeleteFlowGraph(flowId)
    Set t = ..Shape("sentai.dispatch.ScheduledFlowTask", "SentaiTask: "_flowId_"#01")
    Do $$$AssertEquals(t.origin.flowId, flowId)
    Do $$$AssertNotTrue(t.origin.flowExists)
}

Method TestProductTaskDestructivenessComesFromItsStep()
{
    Set flowId = ..CreateSupportedFlow("OriginStep")
    Set t = ..Shape("sentai.dispatch.ScheduledFlowTask", "SentaiTask: "_flowId_"#01")
    Do $$$AssertNotTrue(t.destructive)
    Do $$$AssertNotTrue(t.destructiveUnknown, "integrity-check step: known, not destructive")
    Do ..DeleteFlowGraph(flowId)
}

Method TestProductTaskWithoutItsStepOrFlowIsUnknown()
{
    Set flowId = ..CreateSupportedFlow("OriginNoStep")
    Set t = ..Shape("sentai.dispatch.ScheduledFlowTask", "SentaiTask: "_flowId_"#99")
    Do $$$AssertTrue(t.destructiveUnknown, "step missing")
    Do ..DeleteFlowGraph(flowId)
    Set t = ..Shape("sentai.dispatch.ScheduledFlowTask", "SentaiTask: "_flowId_"#01")
    Do $$$AssertTrue(t.destructiveUnknown, "flow deleted")
}

Method TestProductClassWithAForeignNameIsUnknownAndUnmarked()
{
    Set t = ..Shape("sentai.dispatch.ScheduledFlowTask", "Nightly maintenance")
    Do $$$AssertNotTrue(t.%IsDefined("origin"))
    Do $$$AssertTrue(t.destructiveUnknown)
}

/// List level (analysis I4): the corrected `suspended` drives the filter and the counts.
Method TestSuspendedFilterCountsOnInfo()
{
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptList([
        (##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(1, "Switch Journal", "%SYS", 0)),
        (##class(sentai.unittest.catalog.CatalogFixtures).ListEntry(4, "Integrity Check", "%SYS", 0))
    ])
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(1, "Switch Journal", "%SYS.Task.SwitchJournal", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(0))
    Do ##class(sentai.unittest.catalog.CatalogFixtures).ScriptTask(4, "Integrity Check", "%SYS.Task.IntegrityCheck", ##class(sentai.unittest.catalog.CatalogFixtures).InfoResult(1))
    Set out = ##class(sentai.catalog.TaskService).List("fake-token", "", "", "suspended").body
    Do $$$AssertEquals(out.total, 2)
    Do $$$AssertEquals(out.matched, 1)
    Do $$$AssertEquals(out.items.%Get(0).taskId, 4)
}

}
