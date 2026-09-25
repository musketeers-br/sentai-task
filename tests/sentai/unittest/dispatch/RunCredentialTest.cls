/// E-1: a run renews its own credential. The access token lasts 60 s; with the refresh token of
/// a sign-in dedicated to the run (dispatch body `runCredential`), the loop renews the pair before
/// it expires, and erases both when the run ends.
Class sentai.unittest.dispatch.RunCredentialTest Extends sentai.unittest.SentaiTestCase
{

Method NewRun() As sentai.model.Run
{
    Set id = ..CreateSupportedFlow("RunCredentialFixture")
    Quit ..DispatchUngated(id)
}

Method TestAgedTokenIsRenewedWithTheRefreshToken()
{
    Set run = ..NewRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "access-1", "refresh-1")
    Set ^sentaiRun(run.guid, "%tokenAt") = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 50
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/refresh", "POST", 200, "", "{""access_token"":""access-2"",""refresh_token"":""refresh-2""}")

    Set token = ##class(sentai.dispatch.WaveDispatcher).RenewRunCredentialIfDue(run.guid)

    Do $$$AssertEquals(token, "access-2")
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).RunToken(run.guid), "access-2")
    Do $$$AssertEquals($G(^sentaiRun(run.guid, "%token")), "access-2")
    Do $$$AssertEquals($G(^sentaiRun(run.guid, "%refresh")), "refresh-2")
    Set posted = $G(^sentaiTestDouble("posted", "/api/admin/refresh"))
    Do $$$AssertTrue($LG(posted, 2) [ """refresh_token"":""refresh-1""", "the platform refresh contract is used")
}

Method TestFreshTokenIsNotRenewed()
{
    Set run = ..NewRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "access-1", "refresh-1")
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).RenewRunCredentialIfDue(run.guid), "access-1")
    Do $$$AssertEquals($D(^sentaiTestDouble("posted", "/api/admin/refresh")), 0)
}

Method TestWithoutRefreshTokenTheV1BehaviourIsUnchanged()
{
    Set run = ..NewRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "access-1", "")
    Set ^sentaiRun(run.guid, "%tokenAt") = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 50
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).RenewRunCredentialIfDue(run.guid), "access-1")
    Do $$$AssertEquals($D(^sentaiTestDouble("posted", "/api/admin/refresh")), 0)
}

Method TestRefusedRenewalKeepsTheCurrentToken()
{
    Set run = ..NewRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "access-1", "refresh-1")
    Set ^sentaiRun(run.guid, "%tokenAt") = ##class(sentai.dispatch.WaveDispatcher).NowSeconds() - 50
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/refresh", "POST", 401, "", "")
    // The platform's later 401 on the step is then the recorded failure, as documented for v1.
    Do $$$AssertEquals(##class(sentai.dispatch.WaveDispatcher).RenewRunCredentialIfDue(run.guid), "access-1")
}

Method TestCredentialsAreErasedWhenTheRunEnds()
{
    Set run = ..NewRun()
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, "access-1", "refresh-1")
    Do ##class(sentai.dispatch.WaveDispatcher).CancelRun(run.guid)
    Do ##class(sentai.dispatch.WaveDispatcher).FinalizeRun(run)
    Do $$$AssertEquals($D(^sentaiRun(run.guid, "%token")), 0)
    Do $$$AssertEquals($D(^sentaiRun(run.guid, "%refresh")), 0)
    Do $$$AssertEquals($D(^sentaiRun(run.guid, "%tokenAt")), 0)
}

}
