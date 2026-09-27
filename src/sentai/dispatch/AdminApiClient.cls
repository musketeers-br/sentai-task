/// Thin HTTP client to the administrative API validated in 001-validate-async-job-contract
/// (compatibility.md): the same instance's by default, or a target server's (spec 008) when a
/// base URL is given. Shared by WaveDispatcher, CategoryService, TargetService and the REST
/// dispatcher's token-validation fallback (research.md R-002). No credential is ever hardcoded
/// here; the caller always supplies the operator's own Bearer token, forwarded byte-for-byte
/// (FR-042), or, for Login, the operator's own user name and password, never kept.
Class sentai.dispatch.AdminApiClient Extends %RegisteredObject
{

/// Base host/port for the administrative API — the same IRIS instance's private web
/// server. Read from the %CSP.WebRequest issuing the original call whenever possible;
/// defaults to loopback on the standard private-webserver port for background-job use.
Parameter DefaultHost = "127.0.0.1";

Parameter DefaultPort = 52773;

/// Spec 008 R-4: a target that does not answer is reported within this bound (seconds). The
/// connection attempt has its own timeout (TargetOpenTimeout), measured in T001 as the slow part.
Parameter TargetTimeout = 10;

Parameter TargetOpenTimeout = 5;

/// TLS client configuration for https targets, created by the installer (iris.script).
Parameter TargetSSLConfiguration = "SentaiTargets";

/// `baseUrl` "" = this instance; otherwise `scheme://host:port` of a target server.
ClassMethod NewRequest(bearerToken As %String, baseUrl As %String = "") As %Net.HttpRequest
{
    Set req = ##class(%Net.HttpRequest).%New()
    If (baseUrl = "") {
        Set req.Server = ..#DefaultHost
        Set req.Port = ..#DefaultPort
        Set req.SSLConfiguration = ""
    } Else {
        Set scheme = $ZCVT($PIECE(baseUrl, "://", 1), "L"), hostPort = $PIECE(baseUrl, "://", 2)
        Set req.Server = $PIECE(hostPort, ":", 1)
        Set req.Port = +$PIECE(hostPort, ":", 2)
        If (scheme = "https") {
            Set req.Https = 1
            Set req.SSLConfiguration = ..#TargetSSLConfiguration
        }
        Set req.Timeout = ..#TargetTimeout
        Set req.OpenTimeout = ..#TargetOpenTimeout
    }
    Do:(bearerToken '= "") req.SetHeader("Authorization", "Bearer "_bearerToken)
    Do req.SetHeader("Content-Type", "application/json")
    Quit req
}

/// GET urlPath (query string already embedded). Returns the parsed JSON body (or "" on a
/// non-2xx/parse failure) and, by reference, the raw HTTP status and the Location header
/// (used by StartAsyncJob's callers to obtain the async-result id). With no HTTP answer,
/// `httpStatus` is 0 and `transportError` holds the platform's error text verbatim.
ClassMethod Get(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Get(urlPath, bearerToken, .httpStatus, .locationHeader, baseUrl, .transportError)
    }
    Set req = ..NewRequest(bearerToken, baseUrl)
    Quit ..Send(req, "Get", urlPath, .httpStatus, .locationHeader, .transportError)
}

/// POST urlPath with `body` (a %DynamicObject, or "" for an empty POST as the admin API
/// expects for its async start endpoints).
ClassMethod Post(urlPath As %String, bearerToken As %String, body As %DynamicObject = "", ByRef httpStatus As %Integer, ByRef locationHeader As %String, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Post(urlPath, bearerToken, body, .httpStatus, .locationHeader, baseUrl, .transportError)
    }
    Set req = ..NewRequest(bearerToken, baseUrl)
    If (body '= "") {
        Do req.EntityBody.Write(body.%ToJSON())
    }
    Quit ..Send(req, "Post", urlPath, .httpStatus, .locationHeader, .transportError)
}

/// PUT urlPath (query string already embedded) with `body` — the WQM category write contract
/// (spec 001 evidence 10a). Same return values as Post.
ClassMethod Put(urlPath As %String, bearerToken As %String, body As %DynamicObject = "", ByRef httpStatus As %Integer, ByRef locationHeader As %String, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Put(urlPath, bearerToken, body, .httpStatus, .locationHeader, baseUrl, .transportError)
    }
    Set req = ..NewRequest(bearerToken, baseUrl)
    If (body '= "") {
        Do req.EntityBody.Write(body.%ToJSON())
    }
    Quit ..Send(req, "Put", urlPath, .httpStatus, .locationHeader, .transportError)
}

/// DELETE urlPath (query string already embedded), e.g. `/api/admin/v2/task?id=<n>`.
ClassMethod Delete(urlPath As %String, bearerToken As %String, ByRef httpStatus As %Integer, baseUrl As %String = "", ByRef transportError As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Delete(urlPath, bearerToken, .httpStatus, baseUrl, .transportError)
    }
    Set req = ..NewRequest(bearerToken, baseUrl)
    Quit ..Send(req, "Delete", urlPath, .httpStatus, .location, .transportError)
}

/// Spec 008 FR-022: signs `user` in to the administrative API at `baseUrl` (evidence
/// t0-target-calls 01) and returns its answer — the credential pair and `sub` on 200, the
/// platform's refusal otherwise. The password is used for this one request and not kept.
ClassMethod Login(baseUrl As %String, user As %String, password As %String, ByRef httpStatus As %Integer, ByRef transportError As %String) As %DynamicObject
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit ##class(sentai.unittest.AdminApiDouble).Login(baseUrl, user, .httpStatus, .transportError)
    }
    Set req = ..NewRequest("", baseUrl)
    Do req.SetHeader("Authorization", "Basic "_$SYSTEM.Encryption.Base64Encode(user_":"_password))
    Do req.EntityBody.Write("{}")
    Quit ..Send(req, "Post", "/api/admin/login", .httpStatus, .location, .transportError)
}

/// Sends `req` and turns the outcome into values: the parsed body, the HTTP status and Location,
/// or status 0 with the transport error text when no HTTP answer arrived (research R-4). On such
/// a failure HttpResponse is not an object, so it is never read (T001).
ClassMethod Send(req As %Net.HttpRequest, method As %String, urlPath As %String, ByRef httpStatus As %Integer, ByRef locationHeader As %String, ByRef transportError As %String) As %DynamicObject
{
    Set httpStatus = 0, locationHeader = "", transportError = ""
    Set sc = $METHOD(req, method, urlPath)
    If $$$ISERR(sc) || '$IsObject(req.HttpResponse) {
        Set transportError = $S($$$ISERR(sc):$SYSTEM.Status.GetErrorText(sc), 1:"no HTTP response")
        Quit ""
    }
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
