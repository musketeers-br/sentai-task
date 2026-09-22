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
/// call (via $H) so repeated test runs never collide on the unique name index.
Method CanonicalFlowPayload(namePrefix As %String = "Canonical") As %DynamicObject
{
    Set json = "{"
        _ "  ""schemaVersion"": 1,"
        _ "  ""name"": """_namePrefix_"-"_$TR($H, ",", "-")_""","
        _ "  ""defaultCategory"": ""SENTAI.NIGHT"","
        _ "  ""steps"": ["
        _ "    {""id"":""01"",""type"":""integrity-check"",""taskName"":""IC USER"",""namespace"":""USER"",""databaseDirectory"":""/opt/iris/mgr/user/"",""runAsUser"":""irisadm"",""timeoutMinutes"":90,""wqmCategory"":""SENTAI.NIGHT""},"
        _ "    {""id"":""02"",""type"":""integrity-check"",""taskName"":""IC SAMPLES"",""namespace"":""SAMPLES"",""databaseDirectory"":""/opt/iris/mgr/samples/"",""runAsUser"":""irisadm"",""timeoutMinutes"":45,""wqmCategory"":""SENTAI.NIGHT""},"
        _ "    {""id"":""03"",""type"":""integrity-check"",""taskName"":""IC DOCBOOK"",""namespace"":""DOCBOOK"",""databaseDirectory"":""/opt/iris/mgr/docbook/"",""runAsUser"":""irisadm"",""timeoutMinutes"":45,""wqmCategory"":""SENTAI.NIGHT""},"
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

/// Persists the canonical flow and returns its id.
Method CreateCanonicalFlow(namePrefix As %String = "Canonical") As %String
{
    Set payload = ..CanonicalFlowPayload(namePrefix)
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "testuser", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

}
