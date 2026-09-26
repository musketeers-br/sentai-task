/// Shared base for every sentai.unittest.* suite: enables the administrative-API test
/// double (research.md R-012) before each test and resets it after, and provides the
/// canonical five-step graph (three checks -> purge -> journal switch) used across
/// User Story 1/2/3 tests (flow-definition.schema.json §examples).
Class sentai.unittest.SentaiTestCase Extends %UnitTest.TestCase
{

Method OnBeforeOneTest() As %Status
{
    Do ##class(sentai.unittest.AdminApiDouble).Reset()
    Do ##class(sentai.unittest.AdminApiDouble).Enable()
    // The platform's category list (spec 001 evidence 09 shape): the three built-ins report
    // MaxWorkers/MaxTotalWorkers = 0 ("unbounded"); SENTAI.NIGHT is the canonical fixture's.
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wqm-categories", "GET", 200, "", ..CategoriesJSON())
    Quit $$$OK
}

ClassMethod CategoriesJSON() As %String
{
    Set result = []
    For name = "Default", "SQL", "Utility" {
        Do result.%Push({"Name": (name), "DefaultWorkers": 1, "MaxActiveWorkers": 2, "MaxWorkers": 0, "MaxTotalWorkers": 0, "AlwaysQueue": true})
    }
    Do result.%Push({"Name": "SENTAI.NIGHT", "DefaultWorkers": 1, "MaxActiveWorkers": 2, "MaxWorkers": 4, "MaxTotalWorkers": 8, "AlwaysQueue": true})
    Quit {"status": {"errors": [], "summary": ""}, "console": [], "result": (result)}.%ToJSON()
}

Method OnAfterOneTest() As %Status
{
    Do ##class(sentai.unittest.AdminApiDouble).Reset()
    Quit $$$OK
}

/// Builds the canonical flow payload as a %DynamicObject, with `name` made unique per
/// call so repeated test runs, and several calls within the same second, never collide on
/// the unique name index. The three integrity checks target namespaces and database
/// directories that exist on the instance running the suite, so the canonical flow
/// validates clean and only a test's own mutation produces findings.
Method CanonicalFlowPayload(namePrefix As %String = "Canonical") As %DynamicObject
{
    Set dirUser = ..DatabaseDirectoryOf("USER")
    Set dirApp = ..DatabaseDirectoryOf($NAMESPACE)
    Set dirSys = ..DatabaseDirectoryOf("%SYS")
    Set json = "{"
        _ "  ""schemaVersion"": 1,"
        _ "  ""name"": """_namePrefix_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)_""","
        _ "  ""defaultCategory"": ""SENTAI.NIGHT"","
        _ "  ""steps"": ["
        _ "    {""id"":""01"",""type"":""integrity-check"",""taskName"":""IC USER"",""namespace"":""USER"",""databaseDirectory"":"""_dirUser_""",""runAsUser"":""irisadm"",""timeoutMinutes"":90,""wqmCategory"":""SENTAI.NIGHT""},"
        _ "    {""id"":""02"",""type"":""integrity-check"",""taskName"":""IC APP"",""namespace"":"""_$NAMESPACE_""",""databaseDirectory"":"""_dirApp_""",""runAsUser"":""irisadm"",""timeoutMinutes"":45,""wqmCategory"":""SENTAI.NIGHT""},"
        _ "    {""id"":""03"",""type"":""integrity-check"",""taskName"":""IC IRISSYS"",""namespace"":""%SYS"",""databaseDirectory"":"""_dirSys_""",""runAsUser"":""irisadm"",""timeoutMinutes"":45,""wqmCategory"":""SENTAI.NIGHT""},"
        _ "    {""id"":""04"",""type"":""purge-audit-records"",""taskName"":""Purge audit"",""namespace"":""%SYS"",""runAsUser"":""irisadm"",""timeoutMinutes"":20,""wqmCategory"":""SENTAI.NIGHT"",""parameters"":{""daysToKeep"":30}},"
        _ "    {""id"":""05"",""type"":""switch-journal"",""taskName"":""Switch journal"",""namespace"":""%SYS"",""runAsUser"":""irisadm"",""timeoutMinutes"":5,""wqmCategory"":""SENTAI.NIGHT""}"
        _ "  ],"
        _ "  ""edges"": ["
        _ "    {""source"":""01"",""target"":""04""},"
        _ "    {""source"":""02"",""target"":""04""},"
        _ "    {""source"":""03"",""target"":""04""},"
        _ "    {""source"":""04"",""target"":""05""}"
        _ "  ],"
        _ "  ""joins"": [ {""target"":""04"",""policy"":""ALL_MUST_SUCCEED""} ]"
        _ "}"
    Quit {}.%FromJSON(json)
}

/// The typed confirmation the canonical flow's only destructive step (04, purge-audit-records
/// in %SYS) requires before WaveDispatcher.Dispatch will start anything (FR-017, SC-006).
Method CanonicalConfirmations() As %DynamicArray
{
    Quit [{"stepId": "04", "typedName": "%SYS"}]
}

/// The canonical graph with its only destructive step (04, purge-audit-records) swapped for a
/// non-destructive type — same five steps, same fan-in join — the shape v1 allows /schedule
/// to accept (scheduling of destructive flows is out of scope, spec.md Change Log 2026-09-22).
Method NonDestructiveFlowPayload(namePrefix As %String = "NonDestructive") As %DynamicObject
{
    Set payload = ..CanonicalFlowPayload(namePrefix)
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        Continue:(s.id '= "04")
        Do s.%Set("type", "compact-globals")
        Do s.%Set("taskName", "Compact globals")
        Do s.%Remove("parameters")
    }
    Quit payload
}

/// Count of native scheduled tasks created by /schedule for `flowId` (named "SentaiTask: <flowId>#<stepId>").
ClassMethod NativeTaskCountFor(flowId As %String) As %Integer
{
    Set prefix = "SentaiTask: "_flowId_"#"
    &sql(SELECT COUNT(*) INTO :count FROM %SYS.Task WHERE Name %STARTSWITH :prefix)
    Quit +$G(count)
}

/// Count of every native scheduled task on the instance.
ClassMethod NativeTaskCount() As %Integer
{
    &sql(SELECT COUNT(*) INTO :count FROM %SYS.Task)
    Quit +$G(count)
}

/// Directory of the default globals database of `namespace` on this instance.
ClassMethod DatabaseDirectoryOf(namespace As %String) As %String
{
    Quit $PIECE(##class(%SYS.Namespace).GetGlobalDest(namespace), "^", 2)
}

/// The v1 acceptance shape (spec 004 D-1: integrity-check only): 01 and 02 run in parallel and
/// fan in to 03 under ALL_MUST_SUCCEED, every step on the built-in `Default` category.
Method SupportedGraphPayload(namePrefix As %String = "Supported") As %DynamicObject
{
    Set payload = {
        "schemaVersion": 1,
        "name": (namePrefix_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)),
        "defaultCategory": "Default",
        "steps": [
            {"id": "01", "type": "integrity-check", "taskName": "IC USER", "namespace": "USER", "databaseDirectory": (..DatabaseDirectoryOf("USER")), "runAsUser": "irisadm", "timeoutMinutes": 90, "wqmCategory": "Default"},
            {"id": "02", "type": "integrity-check", "taskName": "IC APP", "namespace": ($NAMESPACE), "databaseDirectory": (..DatabaseDirectoryOf($NAMESPACE)), "runAsUser": "irisadm", "timeoutMinutes": 45, "wqmCategory": "Default"},
            {"id": "03", "type": "integrity-check", "taskName": "IC IRISSYS", "namespace": "%SYS", "databaseDirectory": (..DatabaseDirectoryOf("%SYS")), "runAsUser": "irisadm", "timeoutMinutes": 45, "wqmCategory": "Default"}
        ],
        "edges": [ {"source": "01", "target": "03"}, {"source": "02", "target": "03"} ],
        "joins": [ {"target": "03", "policy": "ALL_MUST_SUCCEED"} ]
    }
    Quit payload
}

/// Persists the supported flow and returns its id.
Method CreateSupportedFlow(namePrefix As %String = "Supported") As %String
{
    Set sc = ##class(sentai.model.Flow).SaveGraph(..SupportedGraphPayload(namePrefix), "", 0, "testuser", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

/// Run-mechanics fixture: creates the Run and its StepRuns for `flowId` directly, bypassing the
/// validation and confirmation gates on purpose, so tests of cancel/pause/rerun/join/SSE keep
/// using the canonical flow (whose purge and journal steps are not available in v1, spec 004).
Method DispatchUngated(flowId As %String) As sentai.model.Run
{
    Set ec = "", ed = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).CreateRun(flowId, ..CanonicalConfirmations(), "tester", .ec, .ed)
    Do $$$AssertEquals(ec, "")
    Quit run
}

/// Persists the canonical flow and returns its id.
Method CreateCanonicalFlow(namePrefix As %String = "Canonical") As %String
{
    Set payload = ..CanonicalFlowPayload(namePrefix)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "testuser", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

/// Spec 005: persists a flow of the given steps (each at least {"id","type"}; the other fields
/// default to a step on `Default` in this namespace) and edges; returns its id.
Method CreateFlowOf(namePrefix As %String, steps As %DynamicArray, edges As %DynamicArray = "") As %String
{
    Set:(edges = "") edges = []
    Set iter = steps.%GetIterator()
    While iter.%GetNext(.k, .s) {
        Do:'s.%IsDefined("taskName") s.%Set("taskName", s.type_" "_s.id)
        Do:'s.%IsDefined("namespace") s.%Set("namespace", $NAMESPACE)
        Do:'s.%IsDefined("runAsUser") s.%Set("runAsUser", "irisadm")
        Do:'s.%IsDefined("timeoutMinutes") s.%Set("timeoutMinutes", 5)
        Do:'s.%IsDefined("wqmCategory") s.%Set("wqmCategory", "Default")
        If (s.type = "integrity-check") && 's.%IsDefined("databaseDirectory") {
            Do s.%Set("databaseDirectory", ..DatabaseDirectoryOf($NAMESPACE))
        }
    }
    Set payload = {
        "schemaVersion": 1,
        "name": (namePrefix_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)),
        "defaultCategory": "Default",
        "steps": (steps),
        "edges": (edges),
        "joins": []
    }
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "testuser", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

}
