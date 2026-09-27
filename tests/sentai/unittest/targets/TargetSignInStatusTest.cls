/// Spec 008 T005 (US1, FR-005, FR-006, FR-022): signing in to a target through the primary keeps
/// nothing, and the status read reports what the target answered — or that it did not answer —
/// verbatim. Target answers follow evidence/t0-target-calls.json.
Class sentai.unittest.targets.TargetSignInStatusTest Extends sentai.unittest.SentaiTestCase
{

Parameter BASE = "https://sign.example:52773";

Property Name As %String;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Set ..Name = ##class(sentai.unittest.targets.TargetServiceTest).Unique("sign")
    Do ##class(sentai.targets.TargetService).Create({"name": (..Name), "baseUrl": (..#BASE)}, "tester")
    Quit sc
}

Method TestSignInReturnsThePairAndKeepsNothing()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/login", "POST", 200, "", {"access_token": "ACC-1", "refresh_token": "REF-1", "sub": "_SYSTEM", "iat": 1000, "exp": 1060}.%ToJSON())
    Set out = ##class(sentai.targets.TargetService).SignIn(..Name, {"user": "_SYSTEM", "password": "pw-never-kept"})
    Do $$$AssertEquals(out.httpStatus, 200, out.%ToJSON())
    Do $$$AssertEquals(out.body.target, ..Name)
    Do $$$AssertEquals(out.body.accessToken, "ACC-1")
    Do $$$AssertEquals(out.body.refreshToken, "REF-1")
    Do $$$AssertEquals(out.body.sub, "_SYSTEM")
    Do $$$AssertEquals(out.body.expiresIn, 60)
    Set keys = "", iter = out.body.%GetIterator()
    While iter.%GetNext(.k) { Set keys = keys_k_"," }
    Do $$$AssertEquals(keys, "target,accessToken,refreshToken,sub,expiresIn,")
    // The product keeps neither the password nor the pair (the double's own script holds the pair,
    // so only the password is checked there).
    For text = "pw-never-kept", "ACC-1", "REF-1" {
        For global = "^sentai", "^sentaiRun", "^IRIS.Temp.sentaiTargetCred" {
            Do $$$AssertNotTrue(##class(sentai.unittest.dispatch.AdminApiClientTargetTest).GlobalContains(global, text), text_" not kept in "_global)
        }
    }
    Do $$$AssertNotTrue(##class(sentai.unittest.dispatch.AdminApiClientTargetTest).GlobalContains("^sentaiTestDouble", "pw-never-kept"))
}

Method TestSignInRefusedUnreachableOfflineAndMissing()
{
    // A wrong password: the target's 401, whose body is empty on 2026.2 (t0 01b).
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/login", "POST", 401, "", "")
    Set out = ##class(sentai.targets.TargetService).SignIn(..Name, {"user": "_SYSTEM", "password": "wrong"})
    Do $$$AssertEquals(out.httpStatus, 401)
    Do $$$AssertEquals(out.problem.detail, "")

    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: Unable to open TCP/IP socket to server sign.example:52773")
    Set out = ##class(sentai.targets.TargetService).SignIn(..Name, {"user": "_SYSTEM", "password": "pw"})
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertEquals(out.problem.detail, "TARGET_UNREACHABLE: ERROR #6059: Unable to open TCP/IP socket to server sign.example:52773")
    Do ##class(sentai.unittest.AdminApiDouble).ScriptUp(..#BASE)

    Do $$$AssertEquals(##class(sentai.targets.TargetService).SignIn(..Name, {"user": "_SYSTEM"}).httpStatus, 400)
    Do ##class(sentai.targets.TargetService).SetOnline(..Name, {"online": false}, "tester")
    Set out = ##class(sentai.targets.TargetService).SignIn(..Name, {"user": "_SYSTEM", "password": "pw"})
    Do $$$AssertEquals(out.httpStatus, 409)
    Do $$$AssertTrue(out.problem.detail [ "TARGET_OFFLINE")
    Do $$$AssertEquals(##class(sentai.targets.TargetService).SignIn("no-such-target", {"user": "u", "password": "p"}).httpStatus, 404)
}

Method TestStatusReportsWhatTheTargetAnswered()
{
    Set categories = [{"Name": "Default", "MaxActiveWorkers": "Dynamic (40)", "DefaultWorkers": "Dynamic (20)", "MaxWorkers": "Dynamic (40)", "MaxTotalWorkers": 0, "AlwaysQueue": false}]
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/info", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": {"serverVersion": "IRIS 2026.2 (Build 221U)", "username": "_SYSTEM", "namespaces": [{"name": "%SYS"}, {"name": "USER"}]}}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/v2/wqm-categories", "GET", 200, "", {"status": {"errors": [], "summary": ""}, "result": (categories)}.%ToJSON())

    Set out = ##class(sentai.targets.TargetService).Status(..Name, "TGT-TOKEN")
    Do $$$AssertEquals(out.httpStatus, 200, out.%ToJSON())
    Do $$$AssertEquals(out.body.target, ..Name)
    Do $$$AssertEquals(out.body.reachable, 1)
    Do $$$AssertEquals(out.body.version, "IRIS 2026.2 (Build 221U)")
    Do $$$AssertEquals(out.body.user, "_SYSTEM")
    Do $$$AssertEquals(out.body.categories.%ToJSON(), categories.%ToJSON(), "categories verbatim")
    Do $$$AssertNotTrue(out.body.categories."0".%IsDefined("queueLength"), "no queue length: the platform does not report one (T001, R-2)")
    Do $$$AssertTrue(out.body.readAt '= "")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), "TGT-TOKEN", "read with the operator's token for the target")
}

Method TestStatusUnreachableRefusedAndMissingHeader()
{
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#BASE, "ERROR #6059: Unable to open TCP/IP socket to server sign.example:52773")
    Set out = ##class(sentai.targets.TargetService).Status(..Name, "TGT")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertEquals(out.body.reachable, 0)
    Do $$$AssertEquals(out.body.unreachable.transportError, "ERROR #6059: Unable to open TCP/IP socket to server sign.example:52773")
    Do $$$AssertNotTrue(out.body.%IsDefined("version"), "nothing invented")
    Do ##class(sentai.unittest.AdminApiDouble).ScriptUp(..#BASE)

    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/info", "GET", 401, "", "")
    Set out = ##class(sentai.targets.TargetService).Status(..Name, "TGT")
    Do $$$AssertEquals(out.body.reachable, 1, "it answered")
    Do $$$AssertEquals(out.body.refused.httpStatus, 401)
    Do $$$AssertEquals(out.body.refused.detail, "")

    Do $$$AssertEquals(##class(sentai.targets.TargetService).Status(..Name, "").httpStatus, 400)
    Do $$$AssertEquals(##class(sentai.targets.TargetService).Status("no-such-target", "TGT").httpStatus, 404)
}

/// The routes: sign-in body in, status header in (contracts/api-delta.md).
Method TestRoutes()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#BASE_"/api/admin/login", "POST", 200, "", {"access_token": "A", "refresh_token": "R", "sub": "_SYSTEM", "iat": 1, "exp": 61}.%ToJSON())
    Do ##class(sentai.unittest.targets.TargetRestTest).Request({"user": "_SYSTEM", "password": "pw"})
    Do ##class(sentai.rest.Dispatcher).SignInToTarget(..Name)
    Do $$$AssertEquals(%response.Status, 200)

    Do ##class(sentai.unittest.targets.TargetRestTest).Request()
    Do ##class(sentai.rest.Dispatcher).ReadTargetStatus(..Name)
    Do $$$AssertEquals(%response.Status, 400, "no target credential header")

    Do ##class(sentai.unittest.targets.TargetRestTest).Request()
    Set %request.CgiEnvs("HTTP_X_SENTAI_TARGET_AUTHORIZATION") = "Bearer A"
    Do ##class(sentai.rest.Dispatcher).ReadTargetStatus(..Name)
    Do $$$AssertEquals(%response.Status, 200)
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#BASE_"/api/admin/info")), "A")
}

}
