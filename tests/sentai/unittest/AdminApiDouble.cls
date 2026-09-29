/// Test double for sentai.dispatch.AdminApiClient, per research.md R-012 ("the call to the
/// administrative API replaced by a test double"). Activated only when
/// ^sentaiTestDouble("enabled") is set — done by TestCase setup, never in production.
/// Tests script canned responses via ^sentaiTestDouble("response", urlPath, "GET"|"POST") =
/// $LB(httpStatus, locationHeader, jsonBodyText); a missing entry defaults to 200/{}.
/// Spec 008: a call to a target server is keyed by `baseUrl_urlPath` (script it with the full
/// URL), and a target scripted with ScriptDown answers nothing: status 0 + the transport error.
Class sentai.unittest.AdminApiDouble Extends %RegisteredObject
{

ClassMethod Get(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    Quit:..IsDown(baseUrl, .httpStatus, .locationHeader, .transportError) ""
    Set urlPath = baseUrl_urlPath
    // Recorded with the credential used, so tests can assert who read what, and how often.
    Set ^sentaiTestDouble("gets", urlPath) = bearerToken
    Set ^sentaiTestDouble("getcount", urlPath) = $G(^sentaiTestDouble("getcount", urlPath)) + 1
    Quit ..Respond(urlPath, "GET", .httpStatus, .locationHeader)
}

ClassMethod Post(urlPath As %String, bearerToken As %String, body As %DynamicObject, ByRef httpStatus As %Integer, ByRef locationHeader As %String, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    Quit:..IsDown(baseUrl, .httpStatus, .locationHeader, .transportError) ""
    Set urlPath = baseUrl_urlPath
    // Strip a trailing query string (?id=...) so pause/resume/cancel calls keyed by base
    // path still match a scripted response.
    Set basePath = $PIECE(urlPath, "?", 1)
    // Recorded so tests can assert the request shape the platform requires (spec 001 evidence).
    Set ^sentaiTestDouble("posted", basePath) = $LB(urlPath, $S($IsObject(body):body.%ToJSON(), 1:""))
    // Every POST in order, with the credential used (spec 005 close-out: one create per step).
    Set n = $I(^sentaiTestDouble("postlog"))
    Set ^sentaiTestDouble("postlog", n) = $LB(urlPath, $S($IsObject(body):body.%ToJSON(), 1:""), bearerToken)
    Quit ..Respond(basePath, "POST", .httpStatus, .locationHeader)
}

ClassMethod Delete(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    Quit:..IsDown(baseUrl, .httpStatus, .location, .transportError) ""
    Set urlPath = baseUrl_urlPath
    // Recorded with the credential used, keyed by the full URL (the id is in the query string).
    Set ^sentaiTestDouble("deleted", urlPath) = bearerToken
    Quit ..Respond($PIECE(urlPath, "?", 1), "DELETE", .httpStatus, .location)
}

ClassMethod Put(urlPath As %String, bearerToken As %String, body As %DynamicObject, ByRef httpStatus As %Integer, ByRef locationHeader As %String, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    Quit:..IsDown(baseUrl, .httpStatus, .locationHeader, .transportError) ""
    Set urlPath = baseUrl_urlPath
    // Same keying as Post: the query string (?name=...) is stripped for the scripted response and
    // the full URL is recorded, so tests can assert the validated contract (spec 001 evidence 10a).
    Set basePath = $PIECE(urlPath, "?", 1)
    Set ^sentaiTestDouble("put", basePath) = $LB(urlPath, $S($IsObject(body):body.%ToJSON(), 1:""))
    Quit ..Respond(basePath, "PUT", .httpStatus, .locationHeader)
}

ClassMethod Respond(urlPath As %String, method As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    Set entry = $G(^sentaiTestDouble("response", urlPath, method))
    If (entry = "") {
        Set httpStatus = 200, locationHeader = ""
        Quit {}
    }
    Set httpStatus = $LG(entry, 1)
    Set locationHeader = $LG(entry, 2)
    Set bodyText = $LG(entry, 3)
    If (bodyText = "") Quit {}
    Quit ##class(%DynamicAbstractObject).%FromJSON(bodyText)
}

/// Spec 008 FR-022: records who signed in to which instance — never the password, which the
/// client does not even pass here — and answers from the script for `baseUrl/api/admin/login`.
ClassMethod Login(baseUrl As %String, user As %String, ByRef httpStatus As %Integer, ByRef transportError As %String) As %DynamicObject
{
    Quit:..IsDown(baseUrl, .httpStatus, .location, .transportError) ""
    Set ^sentaiTestDouble("login", $S(baseUrl = "":"primary", 1:baseUrl)) = user
    Set transportError = ""
    Quit ..Respond(baseUrl_"/api/admin/login", "POST", .httpStatus, .location)
}

/// Spec 015: a sign-in with a wallet secret. Records which secret was used on which instance and
/// answers from the script for `baseUrl/api/admin/login`; `ScriptSecretRefused` makes the platform
/// refuse the secret's use (as `#822` would) before any request.
ClassMethod LoginWithSecret(baseUrl As %String, secretName As %String, ByRef httpStatus As %Integer, ByRef transportError As %String, ByRef secretRefused As %Boolean) As %DynamicObject
{
    Set secretRefused = 0
    Quit:..IsDown(baseUrl, .httpStatus, .location, .transportError) ""
    Set ^sentaiTestDouble("loginSecret", $S(baseUrl = "":"primary", 1:baseUrl)) = secretName
    If $D(^sentaiTestDouble("secretRefused", secretName)) {
        Set httpStatus = 0, transportError = ^sentaiTestDouble("secretRefused", secretName), secretRefused = 1
        Quit ""
    }
    Set transportError = ""
    Quit ..Respond(baseUrl_"/api/admin/login", "POST", .httpStatus, .location)
}

/// Test helper: the platform refuses to let this process use `secretName`.
ClassMethod ScriptSecretRefused(secretName As %String, text As %String = "ERROR #822: Access Denied") As %Status
{
    Set ^sentaiTestDouble("secretRefused", secretName) = text
    Quit $$$OK
}

/// True, with status 0 and the scripted transport error, when `baseUrl` was scripted down.
ClassMethod IsDown(baseUrl As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String, ByRef transportError As %String) As %Boolean
{
    Set transportError = ""
    Quit:(baseUrl = "") 0
    Quit:'$D(^sentaiTestDouble("down", baseUrl)) 0
    Set ^sentaiTestDouble("downcalls", baseUrl) = $G(^sentaiTestDouble("downcalls", baseUrl)) + 1
    Set httpStatus = 0, locationHeader = "", transportError = ^sentaiTestDouble("down", baseUrl)
    Quit 1
}

/// Test helper: the instance at `baseUrl` stops answering (no HTTP response at all).
ClassMethod ScriptDown(baseUrl As %String, transportError As %String) As %Status
{
    Set ^sentaiTestDouble("down", baseUrl) = transportError
    Quit $$$OK
}

/// Test helper: the instance at `baseUrl` answers again.
ClassMethod ScriptUp(baseUrl As %String) As %Status
{
    Kill ^sentaiTestDouble("down", baseUrl)
    Quit $$$OK
}

/// Test helper: scripts one canned response.
ClassMethod Script(urlPath As %String, method As %String, httpStatus As %Integer, locationHeader As %String = "", bodyJSON As %String = "") As %Status
{
    Set ^sentaiTestDouble("response", urlPath, method) = $LB(httpStatus, locationHeader, bodyJSON)
    Quit $$$OK
}

ClassMethod Enable() As %Status
{
    Set ^sentaiTestDouble("enabled") = 1
    Quit $$$OK
}

ClassMethod Reset() As %Status
{
    Kill ^sentaiTestDouble
    Quit $$$OK
}

}
