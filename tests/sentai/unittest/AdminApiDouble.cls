/// Test double for sentai.dispatch.AdminApiClient, per research.md R-012 ("the call to the
/// administrative API replaced by a test double"). Activated only when
/// ^sentaiTestDouble("enabled") is set — done by TestCase setup, never in production.
/// Tests script canned responses via ^sentaiTestDouble("response", urlPath, "GET"|"POST") =
/// $LB(httpStatus, locationHeader, jsonBodyText); a missing entry defaults to 200/{}.
Class sentai.unittest.AdminApiDouble Extends %RegisteredObject
{

ClassMethod Get(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    // Recorded with the credential used, so tests can assert who read what.
    Set ^sentaiTestDouble("gets", urlPath) = bearerToken
    Quit ..Respond(urlPath, "GET", .httpStatus, .locationHeader)
}

ClassMethod Post(urlPath As %String, bearerToken As %String, body As %DynamicObject, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
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

ClassMethod Delete(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer) As %DynamicObject
{
    // Recorded with the credential used, keyed by the full URL (the id is in the query string).
    Set ^sentaiTestDouble("deleted", urlPath) = bearerToken
    Quit ..Respond($PIECE(urlPath, "?", 1), "DELETE", .httpStatus, .location)
}

ClassMethod Put(urlPath As %String, bearerToken As %String, body As %DynamicObject, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
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
