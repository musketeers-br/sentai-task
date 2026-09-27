/// Spec 008 T007 (US3/US2, FR-010, FR-011, plan D-3/D-5): dispatch takes one credential per
/// target the flow uses, redeems it on that target, checks it is the dispatcher's, keeps the fresh
/// pair only for the run (IRISTEMP), renews it and erases it at the end. Every refusal happens
/// before any run exists.
Class sentai.unittest.dispatch.TargetCredentialTest Extends sentai.unittest.SentaiTestCase
{

Parameter BASE = "https://cred.example:52773";

Property Name As %String;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Set ..Name = ##class(sentai.unittest.targets.TargetServiceTest).Unique("cred")
    Do ##class(sentai.targets.TargetService).Create({"name": (..Name), "baseUrl": (..#BASE)}, "tester")
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/info", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": {"serverVersion": "IRIS 2026.2", "username": ($USERNAME), "namespaces": [{"name": "%SYS"}, {"name": "USER"}]}}.%ToJSON())
    Quit sc
}

/// 01 local, 02 and 03 on the target.
Method RemoteFlow() As %String
{
    Quit ..CreateFlowOf("TargetCred", [{"id": "01", "type": "integrity-check"}, {"id": "02", "type": "integrity-check", "namespace": "USER", "target": (..Name)}, {"id": "03", "type": "integrity-check", "namespace": "USER", "target": (..Name)}])
}

Method ScriptRefresh(sub As %String, access As %String = "FRESH-A", refresh As %String = "FRESH-R")
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/refresh", "POST", 200, "", {"access_token": (access), "refresh_token": (refresh), "sub": (sub), "iat": 1, "exp": 61}.%ToJSON())
}

Method Credentials(refreshToken As %String = "OLD-R") As %DynamicArray
{
    Quit [{"target": (..Name), "refreshToken": (refreshToken)}]
}

Method TestMissingCredentialNamesTargetAndSteps()
{
    Set out = ##class(sentai.targets.TargetService).RedeemForDispatch(..RemoteFlow(), [], $USERNAME, .pairs)
    Do $$$AssertEquals(out.httpStatus, 400)
    Do $$$AssertEquals(out.problem.detail, "TARGET_CREDENTIAL_MISSING: target '"_..Name_"' (steps 02, 03)")
}

Method TestRefusedRedemptionIsTheTargetsAnswer()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/refresh", "POST", 401, "", "")
    Set out = ##class(sentai.targets.TargetService).RedeemForDispatch(..RemoteFlow(), ..Credentials(), $USERNAME, .pairs)
    Do $$$AssertEquals(out.httpStatus, 401)

    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: Unable to open TCP/IP socket to server cred.example:52773")
    Set out = ##class(sentai.targets.TargetService).RedeemForDispatch(..RemoteFlow(), ..Credentials(), $USERNAME, .pairs)
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertEquals(out.problem.detail, "TARGET_UNREACHABLE: target '"_..Name_"': ERROR #6059: Unable to open TCP/IP socket to server cred.example:52773")
}

Method TestAnotherUsersCredentialIsRefused()
{
    Do ..ScriptRefresh("someone-else")
    Set out = ##class(sentai.targets.TargetService).RedeemForDispatch(..RemoteFlow(), ..Credentials(), "operator1", .pairs)
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.detail, "TARGET_CREDENTIAL_USER_MISMATCH: the credential for target '"_..Name_"' belongs to 'someone-else', not to 'operator1'")

    // Letter case alone is not a mismatch (as the local run credential check).
    Do ..ScriptRefresh("OPERATOR1")
    Do $$$AssertEquals(##class(sentai.targets.TargetService).RedeemForDispatch(..RemoteFlow(), ..Credentials(), "operator1", .pairs), "")
}

/// The route refuses before any run exists.
Method TestRouteRefusesWithoutCreatingARun()
{
    Set id = ..RemoteFlow()
    Do ##class(sentai.unittest.targets.TargetRestTest).Request({"confirmations": []})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 400)
    Do $$$AssertEquals(##class(sentai.unittest.validation.StepAvailabilityRuleTest).RunCountFor(id), 0)

    Do ..ScriptRefresh("someone-else")
    Do ##class(sentai.unittest.targets.TargetRestTest).Request({"confirmations": [], "targetCredentials": (..Credentials())})
    Do ##class(sentai.rest.Dispatcher).DispatchFlow(id)
    Do $$$AssertEquals(%response.Status, 403)
    Do $$$AssertEquals(##class(sentai.unittest.validation.StepAvailabilityRuleTest).RunCountFor(id), 0)
}

/// Success: the fresh pair validates the flow and is kept only in IRISTEMP, for this run.
Method TestRedeemedPairValidatesAndIsKeptOnlyForTheRun()
{
    Do ..ScriptRefresh($USERNAME, "FRESH-A1", "FRESH-R1")
    Set id = ..RemoteFlow()
    Do $$$AssertEquals(##class(sentai.targets.TargetService).RedeemForDispatch(id, ..Credentials(), $USERNAME, .pairs), "")
    Do $$$AssertEquals(pairs.%Get(..Name).accessToken, "FRESH-A1")
    Do $$$AssertEquals(pairs.%Get(..Name).baseUrl, ..#BASE)

    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], $USERNAME, .ec, .ed, .report, "", ##class(sentai.dispatch.WaveDispatcher).AccessTokens(pairs))
    Do $$$AssertEquals(ec, "", $S($IsObject(report):report.%ToJSON(), 1:ed))
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), "FRESH-A1", "validated with the redeemed token")

    Do ##class(sentai.dispatch.WaveDispatcher).StoreTargetCredentials(run.guid, pairs)
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).TargetToken(run.guid, ..Name), "FRESH-A1")
    Do $$$AssertNotTrue(##class(sentai.unittest.dispatch.AdminApiClientTargetTest).GlobalContains("^sentaiRun", "FRESH-A1"), "not in the persistent run registry")
    Do $$$AssertNotTrue(##class(sentai.unittest.dispatch.AdminApiClientTargetTest).GlobalContains("^sentaiRun", "FRESH-R1"))

    // FR-011: renewed from the target's own refresh once older than 40 s …
    Set $LIST(^IRIS.Temp.sentaiTargetCred(run.guid, ..Name), 3) = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 41
    Do ..ScriptRefresh($USERNAME, "RENEWED-A", "RENEWED-R")
    Do ##class(sentai.dispatch.WaveDispatcher).RenewTargetCredentialsIfDue(run.guid)
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).TargetToken(run.guid, ..Name), "RENEWED-A")
    Do $$$AssertEquals($LG(^sentaiTestDouble("posted", ..#BASE_"/api/admin/refresh"), 2), {"refresh_token": "FRESH-R1"}.%ToJSON())

    // … and erased when the run ends.
    Do ##class(sentai.dispatch.WaveDispatcher).FinalizeRun(run)
    Do $$$AssertEquals($D(^IRIS.Temp.sentaiTargetCred(run.guid)), 0)
}

}
