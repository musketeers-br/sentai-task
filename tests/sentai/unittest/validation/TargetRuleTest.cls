/// Spec 008 T006 (US3, FR-007…FR-009, plan D-2/D-4): a step may name a target; the catalog says
/// which types can run remotely; validation reports every unusable target per step, by the
/// target's own answers when it has a credential for it, and warns when it has none.
Class sentai.unittest.validation.TargetRuleTest Extends sentai.unittest.SentaiTestCase
{

Parameter BASE = "https://rule.example:52773";

Property Name As %String;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Set ..Name = ##class(sentai.unittest.targets.TargetServiceTest).Unique("rule")
    Do ##class(sentai.targets.TargetService).Create({"name": (..Name), "baseUrl": (..#BASE)}, "tester")
    // The target's own answers (t0-target-calls 00): it has %SYS and USER, not IRISAPP.
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/info", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": {"serverVersion": "IRIS 2026.2", "username": "_SYSTEM", "namespaces": [{"name": "%SYS"}, {"name": "USER"}]}}.%ToJSON())
    Quit sc
}

/// A flow of one step on `target` (namespace defaults to USER, which the target has).
Method OneStepOn(target As %String, type As %String = "integrity-check", namespace As %String = "USER") As %String
{
    Quit ..CreateFlowOf("TargetRule", [{"id": "01", "type": (type), "namespace": (namespace), "target": (target)}])
}

/// {"<this test's target>": token}: the validator's map of target credentials.
Method Tokens(token As %String) As %DynamicObject
{
    Set map = {}
    Do map.%Set(..Name, token)
    Quit map
}

ClassMethod Codes(report As %DynamicObject, list As %String = "errors") As %String
{
    Set codes = "", iter = report.%Get(list).%GetIterator()
    While iter.%GetNext(.k, .f) { Set codes = codes_","_f.code }
    Quit codes
}

ClassMethod Finding(report As %DynamicObject, code As %String, list As %String = "errors") As %DynamicObject
{
    Set iter = report.%Get(list).%GetIterator(), found = ""
    While iter.%GetNext(.k, .f) { If (f.code = code) Set found = f Quit }
    Quit found
}

Method TestStepTargetIsSavedAndReadBack()
{
    Set id = ..OneStepOn(..Name)
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(id, "01", 0)
    Do $$$AssertEquals(step.target, ..Name)
    Set read = ##class(sentai.rest.Dispatcher).ShapeFlow(##class(sentai.model.Flow).%OpenId(id), 1)
    Do $$$AssertEquals(read.steps."0".target, ..Name)

    // Absent = local, and a local step's read shape is exactly today's (no target key).
    Set local = ..CreateFlowOf("TargetRuleLocal", [{"id": "01", "type": "integrity-check"}])
    Set read = ##class(sentai.rest.Dispatcher).ShapeFlow(##class(sentai.model.Flow).%OpenId(local), 1)
    Do $$$AssertNotTrue(read.steps."0".%IsDefined("target"))
}

Method TestCatalogSaysWhichTypesAreRemoteCapable()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsRemoteCapable("integrity-check"), 1)
    For type = "switch-journal", "purge-task-history", "storage-headroom-check", "db-size-report", "custom", "bogus" {
        Do $$$AssertEquals(##class(sentai.registry.StepType).IsRemoteCapable(type), 0, type)
    }
    Set iter = ##class(sentai.registry.StepType).GetCatalog().%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Do $$$AssertEquals(entry.%GetTypeOf("remoteCapable"), "boolean", entry.type)
    }
}

Method TestUnknownAndOfflineTargets()
{
    Set report = ##class(sentai.validation.FlowValidator).Validate(..OneStepOn("no-such-target"), "", {})
    Set f = ..Finding(report, "TARGET_NOT_FOUND")
    Do $$$AssertTrue($IsObject(f), report.%ToJSON())
    Do $$$AssertEquals(f.stepId, "01")
    Do $$$AssertEquals(f.target, "no-such-target")

    Do ##class(sentai.targets.TargetService).SetOnline(..Name, {"online": false}, "tester")
    Set report = ##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name), "", ..Tokens("TGT"))
    Do $$$AssertTrue($IsObject(..Finding(report, "TARGET_OFFLINE")), report.%ToJSON())
    Do $$$AssertEquals($D(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), 0, "an offline target is not called")
}

Method TestInProcessTypesAreNotRemoteCapable()
{
    For type = "switch-journal", "storage-headroom-check", "db-size-report" {
        Set report = ##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name, type), "", ..Tokens("TGT"))
        Set f = ..Finding(report, "STEP_TYPE_NOT_REMOTE_CAPABLE")
        Do $$$AssertTrue($IsObject(f), type_": "_report.%ToJSON())
        Do $$$AssertEquals(f.target, ..Name)
    }
}

Method TestWithACredentialTheTargetsAnswersDecide()
{
    // Reachable, namespace present: no target finding.
    Set report = ##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name), "", ..Tokens("TGT"))
    Do $$$AssertEquals(..Codes(report), "", report.%ToJSON())
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), "TGT", "read with the operator's token for the target")

    // A namespace the target does not have — judged by the target, not the primary.
    Set report = ##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name, "integrity-check", $NAMESPACE), "", ..Tokens("TGT"))
    Do $$$AssertEquals(..Codes(report), ",NAMESPACE_NOT_FOUND", report.%ToJSON())

    // Refused: the target's answer verbatim.
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/info", "GET", 401, "", "")
    Set f = ..Finding(##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name), "", ..Tokens("TGT")), "TARGET_REFUSED")
    Do $$$AssertTrue($IsObject(f))
    Do $$$AssertTrue(f.message [ "HTTP 401", f.message)

    // Unreachable: the transport error verbatim.
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: Unable to open TCP/IP socket to server rule.example:52773")
    Set f = ..Finding(##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name), "", ..Tokens("TGT")), "TARGET_UNREACHABLE")
    Do $$$AssertTrue($IsObject(f))
    Do $$$AssertTrue(f.message [ "ERROR #6059: Unable to open TCP/IP socket to server rule.example:52773", f.message)
    Do $$$AssertEquals(f.stepId, "01")
}

/// Plan D-2: without a credential for the target, a warning — never an error, never a call.
Method TestWithoutACredentialOnlyAWarning()
{
    Set report = ##class(sentai.validation.FlowValidator).Validate(..OneStepOn(..Name), "")
    Do $$$AssertEquals(..Codes(report), "", report.%ToJSON())
    Set w = ..Finding(report, "TARGET_NOT_VERIFIED", "warnings")
    Do $$$AssertTrue($IsObject(w), report.%ToJSON())
    Do $$$AssertEquals(w.target, ..Name)
    Do $$$AssertEquals($D(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), 0)
}

/// FR-019: a flow with no target validates exactly as before.
Method TestLocalFlowReportUnchanged()
{
    Set report = ##class(sentai.validation.FlowValidator).Validate(..CreateSupportedFlow("TargetRuleLocal"), "")
    Do $$$AssertEquals(report.%ToJSON(), {"errors": [], "warnings": []}.%ToJSON())
}

/// The validate route takes the optional target credentials.
Method TestValidateRouteCarriesTargetCredentials()
{
    Set id = ..OneStepOn(..Name)
    Do ##class(sentai.unittest.targets.TargetRestTest).Request({"targetCredentials": [{"target": (..Name), "accessToken": "ROUTE-TGT"}]})
    Do ##class(sentai.rest.Dispatcher).ValidateFlow(id)
    Do $$$AssertEquals(%response.Status, 200)
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), "ROUTE-TGT")
}

}
