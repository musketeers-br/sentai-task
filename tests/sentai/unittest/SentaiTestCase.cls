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
    Quit $$$OK
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

/// Persists the canonical flow and returns its id.
Method CreateCanonicalFlow(namePrefix As %String = "Canonical") As %String
{
    Set payload = ..CanonicalFlowPayload(namePrefix)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "testuser", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

}
