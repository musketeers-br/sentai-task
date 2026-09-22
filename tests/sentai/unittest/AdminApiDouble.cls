/// Test double for sentai.dispatch.AdminApiClient, per research.md R-012 ("the call to the
/// administrative API replaced by a test double"). Activated only when
/// ^sentaiTestDouble("enabled") is set — done by TestCase setup, never in production.
/// Tests script canned responses via ^sentaiTestDouble("response", urlPath, "GET"|"POST") =
/// $LB(httpStatus, locationHeader, jsonBodyText); a missing entry defaults to 200/{}.
Class sentai.unittest.AdminApiDouble Extends %RegisteredObject
{

ClassMethod Get(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    Quit ..Respond(urlPath, "GET", .httpStatus, .locationHeader)
}

ClassMethod Post(urlPath As %String, bearerToken As %String, body As %DynamicObject, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    // Strip a trailing query string (?id=...) so pause/resume/cancel calls keyed by base
    // path still match a scripted response.
    Set basePath = $PIECE(urlPath, "?", 1)
    Quit ..Respond(basePath, "POST", .httpStatus, .locationHeader)
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
