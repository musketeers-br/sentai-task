/// Spec 008 T003 (plan D-1, research R-4): the management-API client reaches another instance
/// by base URL, reports transport errors as values, and signs in with Basic auth — while every
/// call without a base URL behaves exactly as before.
Class sentai.unittest.dispatch.AdminApiClientTargetTest Extends sentai.unittest.SentaiTestCase
{

Parameter TARGET = "http://iris-target:52773";

/// No base URL: today's loopback call, keyed by path only.
Method TestLocalCallUnchanged()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/info", "GET", 200, "", {"result": {"serverVersion": "local"}}.%ToJSON())
    Set body = ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/info", "tok-local", .httpStatus, .location)
    Do $$$AssertEquals(httpStatus, 200)
    Do $$$AssertEquals(body.result.serverVersion, "local")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", "/api/admin/info")), "tok-local")
}

/// A base URL routes the call to that instance's scripted answers, with its own bearer.
Method TestTargetCallIsRoutedByBaseUrl()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/info", "GET", 200, "", {"result": {"serverVersion": "local"}}.%ToJSON())
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#TARGET_"/api/admin/info", "GET", 200, "", {"result": {"serverVersion": "remote"}}.%ToJSON())
    Set body = ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/info", "tok-target", .httpStatus, .location, ..#TARGET, .transportError)
    Do $$$AssertEquals(httpStatus, 200)
    Do $$$AssertEquals(transportError, "")
    Do $$$AssertEquals(body.result.serverVersion, "remote")
    Do $$$AssertEquals($G(^sentaiTestDouble("gets", ..#TARGET_"/api/admin/info")), "tok-target")
    Do $$$AssertEquals($D(^sentaiTestDouble("gets", "/api/admin/info")), 0, "the local instance was not called")

    // POST to the target: recorded under the target, with its query string kept in the log.
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#TARGET_"/api/admin/v2/async-result/cancel", "POST", 200, "", "")
    Do ##class(sentai.dispatch.AdminApiClient).Post("/api/admin/v2/async-result/cancel?id=7", "tok-target", {}, .httpStatus, .location, ..#TARGET, .transportError)
    Do $$$AssertEquals(httpStatus, 200)
    Do $$$AssertEquals($LG($G(^sentaiTestDouble("posted", ..#TARGET_"/api/admin/v2/async-result/cancel")), 1), ..#TARGET_"/api/admin/v2/async-result/cancel?id=7")
}

/// No HTTP answer: status 0 and the transport error verbatim, never an empty success.
Method TestTransportErrorIsAValue()
{
    Set text = "ERROR #6059: Unable to open TCP/IP socket to server iris-target:52773"
    Do ##class(sentai.unittest.AdminApiDouble).ScriptDown(..#TARGET, text)
    Set body = ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/info", "tok", .httpStatus, .location, ..#TARGET, .transportError)
    Do $$$AssertEquals(httpStatus, 0)
    Do $$$AssertEquals(transportError, text)
    Do $$$AssertEquals(body, "")
    Do ##class(sentai.dispatch.AdminApiClient).Post("/api/admin/login", "", {}, .httpStatus, .location, ..#TARGET, .transportError)
    Do $$$AssertEquals(transportError, text)
}

/// Sign-in: Basic auth to the target's login, the pair returned, no password recorded anywhere.
Method TestLoginSendsBasicAndKeepsNoPassword()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#TARGET_"/api/admin/login", "POST", 200, "", {"access_token": "A1", "refresh_token": "R1", "sub": "_SYSTEM", "expires_in": 60}.%ToJSON())
    Set pair = ##class(sentai.dispatch.AdminApiClient).Login(..#TARGET, "_SYSTEM", "s3cret-pw", .httpStatus, .transportError)
    Do $$$AssertEquals(httpStatus, 200)
    Do $$$AssertEquals(pair."access_token", "A1")
    Do $$$AssertEquals(pair.sub, "_SYSTEM")
    Do $$$AssertEquals($G(^sentaiTestDouble("login", ..#TARGET)), "_SYSTEM", "the double saw who signed in")
    Do $$$AssertNotTrue(..GlobalContains("^sentaiTestDouble", "s3cret-pw"), "no password recorded")

    // A refusal comes back as the target's status and body.
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#TARGET_"/api/admin/login", "POST", 401, "", {"errors": [{"error": "ERROR #798: Access Denied"}], "summary": ""}.%ToJSON())
    Set pair = ##class(sentai.dispatch.AdminApiClient).Login(..#TARGET, "_SYSTEM", "wrong", .httpStatus, .transportError)
    Do $$$AssertEquals(httpStatus, 401)
    Do $$$AssertEquals(pair.errors."0".error, "ERROR #798: Access Denied")
}

/// True when any node of `global` holds `text` (walks with $QUERY).
ClassMethod GlobalContains(global As %String, text As %String) As %Boolean
{
    Set node = global, found = 0
    For {
        Set node = $QUERY(@node)
        Quit:(node = "")
        If ($G(@node) [ text) || (node [ text) Set found = 1 Quit
    }
    Quit found
}

}
