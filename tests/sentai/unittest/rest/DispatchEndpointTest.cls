Class sentai.unittest.rest.DispatchEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method NewRequest(bodyObj As %DynamicObject) As %Status
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write(bodyObj.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Quit $$$OK
}

Method TestValidDispatchReturns202WithAllStepsQueued()
{
    Set id = ..CreateSupportedFlow("DispatchOk")
    Do ..NewRequest({"confirmations": []})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 202)

    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai_model.StepRun sr JOIN sentai_model.Run r ON sr.run = r.ID WHERE r.flow = ?")
    Set result = rs.%Execute(id)
    Do result.%Next()
    Do $$$AssertEquals(result.%Get("c"), 3)
}

/// FR-017 still holds: a destructive step without a matching typed confirmation is named as
/// pending. Since spec 004 no v1-available type is destructive, so over HTTP the canonical flow
/// is refused earlier, by validation (422), and never reaches the 428 path.
Method TestMissingDestructiveConfirmationNamesStep()
{
    Set id = ..CreateCanonicalFlow("DispatchNoConfirm")
    Do $$$AssertNotTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, [], .pending))
    Do $$$AssertEquals(pending, "04")
    Do $$$AssertTrue(##class(sentai.dispatch.WaveDispatcher).CheckConfirmations(id, ..CanonicalConfirmations(), .pending))

    Do ..NewRequest({"confirmations": []})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 422)

    // No StepRun should exist for this flow's steps.
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai_model.StepRun sr JOIN sentai_model.Run r ON sr.run = r.ID WHERE r.flow = ?")
    Set result = rs.%Execute(id)
    Do result.%Next()
    Do $$$AssertEquals(result.%Get("c"), 0)
}

Method TestStructuralErrorBlocksDispatchRegardlessOfPriorValidation()
{
    Set payload = ..CanonicalFlowPayload("DispatchStructBad")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Do ..NewRequest({"confirmations": [{"stepId": "04", "typedName": "%SYS"}]})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
}

/// --- Spec 005 T011: one identity per run (plan ID-1, ID-2; research R-8) ---
Method RunsOf(flowId As %String) As %Integer
{
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.Run WHERE flow = :flowId)
    Quit +n
}

Method ScriptRefresh(sub As %String)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/refresh", "POST", 200, "", {"access_token": "fresh-access", "refresh_token": "fresh-refresh", "sub": (sub)}.%ToJSON())
}

Method TestRunCredentialOfAnotherUserIsRefused()
{
    Set id = ..CreateSupportedFlow("DispatchCredOther")
    Do ..ScriptRefresh("someone-else")
    Do ..NewRequest({"confirmations": [], "runCredential": {"refreshToken": "their-refresh"}})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 403)
    Do $$$AssertEquals(..RunsOf(id), 0)
    // The credential was redeemed once, with the refresh token the request carried.
    Do $$$AssertEquals($LG(^sentaiTestDouble("posted", "/api/admin/refresh"), 2), "{""refresh_token"":""their-refresh""}")
}

Method TestRunCredentialOfTheSameUserBecomesTheRunCredential()
{
    Set id = ..CreateSupportedFlow("DispatchCredSame")
    Do ..ScriptRefresh($ZCVT(##class(sentai.rest.Dispatcher).CurrentUser(), "L"))
    Do ..NewRequest({"confirmations": [], "runCredential": {"refreshToken": "my-refresh"}})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 202)
    Do $$$AssertEquals(..RunsOf(id), 1)
    // Redeeming revokes the access token paired with that refresh token — which the canvas also
    // sends as the request's bearer — so the rest of the request (validation's category read)
    // uses the fresh one.
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", "/api/admin/v2/wqm-categories")), "fresh-access")
    // The background loop erases the credential when the run ends, so the stored pair is
    // observed through its use: the run's calls to the platform carry the fresh access token.
    For i = 1:1:50 {
        Set used = ""
        Set n = ""
        For {
            Set n = $O(^sentaiTestDouble("postlog", n))
            Quit:(n = "")
            Set entry = ^sentaiTestDouble("postlog", n)
            Set:($LG(entry, 1) [ "integrity-check") used = $LG(entry, 3)
        }
        Quit:(used '= "")
        Hang 0.1
    }
    Do $$$AssertEquals(used, "fresh-access", "the fresh pair is the run credential")
}

Method TestRefusedRedemptionIs401WithThePlatformsText()
{
    Set id = ..CreateSupportedFlow("DispatchCredBad")
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/refresh", "POST", 401, "", {"status": {"errors": [], "summary": "Invalid refresh token"}}.%ToJSON())
    Do ..NewRequest({"confirmations": [], "runCredential": {"refreshToken": "expired"}})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 401)
    Do $$$AssertEquals(..RunsOf(id), 0)
}

Method RerunRequest(asUser As %String, ByRef run) As %String
{
    Set run = ..DispatchUngated(..CreateSupportedFlow("RerunWho"))
    Set guid = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "failed", "fixture"))
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Kill %session
    Set %session("Username") = asUser
    Quit guid
}

Method TestRerunByAnotherUserIsRefused()
{
    // DispatchUngated dispatches as "tester".
    Set guid = ..RerunRequest("someone-else", .run)
    Do ##class(sentai.rest.Dispatcher).RerunStep(run.guid, guid)
    Kill %session
    Do $$$AssertEquals(%response.Status, 403)
    Do $$$AssertEquals(^sentaiRun(run.guid, "01"), guid, "no new StepRun")
}

Method TestRerunByTheDispatcherIsAccepted()
{
    Set guid = ..RerunRequest("TESTER", .run)
    Do ##class(sentai.rest.Dispatcher).RerunStep(run.guid, guid)
    Kill %session
    Do $$$AssertEquals(%response.Status, 202)
    Do $$$AssertTrue(^sentaiRun(run.guid, "01") '= guid)
}

}
