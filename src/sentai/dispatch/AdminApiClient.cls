/// Thin HTTP client to the same-instance administrative API validated in
/// 001-validate-async-job-contract (compatibility.md). Shared by WaveDispatcher,
/// CategoryService, and the REST dispatcher's token-validation fallback (research.md R-002) —
/// the only three call sites of the administrative API in this codebase. No credential is
/// ever hardcoded here; the caller always supplies the operator's own Bearer token,
/// forwarded byte-for-byte (FR-042).
Class sentai.dispatch.AdminApiClient Extends %RegisteredObject
{

/// Base host/port for the administrative API — the same IRIS instance's private web
/// server. Read from the %CSP.WebRequest issuing the original call whenever possible;
/// defaults to loopback on the standard private-webserver port for background-job use.
Parameter DefaultHost = "127.0.0.1";

Parameter DefaultPort = 52773;

ClassMethod NewRequest(bearerToken As %String) As %Net.HttpRequest
{
    Set req = ##class(%Net.HttpRequest).%New()
    Set req.Server = ..#DefaultHost
    Set req.Port = ..#DefaultPort
    Set req.SSLConfiguration = ""
    Do req.SetHeader("Authorization", "Bearer "_bearerToken)
    Do req.SetHeader("Content-Type", "application/json")
    Quit req
}

/// GET urlPath (query string already embedded). Returns the parsed JSON body (or "" on a
/// non-2xx/parse failure) and, by reference, the raw HTTP status and the Location header
/// (used by StartAsyncJob's callers to obtain the async-result id).
ClassMethod Get(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Get(urlPath, bearerToken, .httpStatus, .locationHeader)
    }
    Set req = ..NewRequest(bearerToken)
    Do req.Get(urlPath)
    Set httpStatus = +req.HttpResponse.StatusCode
    Set locationHeader = req.HttpResponse.GetHeader("LOCATION")
    Quit ..ParseBody(req)
}

/// POST urlPath with `body` (a %DynamicObject, or "" for an empty POST as the admin API
/// expects for its async start endpoints).
ClassMethod Post(urlPath As %String, bearerToken As %String, body As %DynamicObject = "", ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Post(urlPath, bearerToken, body, .httpStatus, .locationHeader)
    }
    Set req = ..NewRequest(bearerToken)
    If (body '= "") {
        Do req.EntityBody.Write(body.%ToJSON())
    }
    Do req.Post(urlPath)
    Set httpStatus = +req.HttpResponse.StatusCode
    Set locationHeader = req.HttpResponse.GetHeader("LOCATION")
    Quit ..ParseBody(req)
}

/// PUT urlPath (query string already embedded) with `body` — the WQM category write contract
/// (spec 001 evidence 10a). Same return values as Post.
ClassMethod Put(urlPath As %String, bearerToken As %String, body As %DynamicObject = "", ByRef httpStatus As %Integer, ByRef locationHeader As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Put(urlPath, bearerToken, body, .httpStatus, .locationHeader)
    }
    Set req = ..NewRequest(bearerToken)
    If (body '= "") {
        Do req.EntityBody.Write(body.%ToJSON())
    }
    Do req.Put(urlPath)
    Set httpStatus = +req.HttpResponse.StatusCode
    Set locationHeader = req.HttpResponse.GetHeader("LOCATION")
    Quit ..ParseBody(req)
}

ClassMethod ParseBody(req As %Net.HttpRequest) As %DynamicObject
{
    Set result = ""
    Try {
        If $IsObject(req.HttpResponse.Data) {
            Set text = req.HttpResponse.Data.Read(req.HttpResponse.Data.Size)
        } Else {
            Set text = ""
        }
        If (text '= "") Set result = ##class(%DynamicAbstractObject).%FromJSON(text)
    }
    Catch {
        Set result = ""
    }
    Quit result
}

}
