/// Exercises the token-validation logic behind OnPreDispatch (FR-040, FR-041, NFR-006)
/// directly, via the administrative-API test double — a live HTTP round trip through the
/// CSP application itself is exercised separately against a real instance (quickstart.md
/// "GET /flows without a token returns 401").
Class sentai.unittest.rest.AuthenticationTest Extends sentai.unittest.SentaiTestCase
{

Method TestValidTokenIsAccepted()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/info", "GET", 200, "", "{}")
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).IsTokenValid("a-valid-looking-token"), 1)
}

Method TestExpiredOrInvalidTokenIsRejected()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/info", "GET", 401, "", "{}")
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).IsTokenValid("an-expired-token"), 0)
}

/// A 403 from the platform proves the token authenticated: the operator is known, only the
/// administrative read is refused. The gate lets the request through so each endpoint returns the
/// platform's own answer for that operator (Constitution III). It grants nothing: the request
/// already runs with the operator's own roles (JWT web app, no MatchRoles).
Method TestAuthenticatedOperatorWithoutAdminPrivilegeIsAccepted()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/info", "GET", 403, "", "{""errors"":[],""summary"":""""}")
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).IsTokenValid("an-unprivileged-operators-token"), 1)
}

Method TestOtherPlatformAnswersAreRejected()
{
    For status = 400, 404, 500, 502 {
        Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/info", "GET", status, "", "{}")
        Do $$$AssertEquals(##class(sentai.rest.Dispatcher).IsTokenValid("a-token"), 0, "HTTP "_status_" is not proof of authentication")
    }
}

Method TestMissingAuthorizationHeaderYieldsEmptyToken()
{
    Kill %request
    Set %request = ##class(%CSP.Request).%New()
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).ExtractBearerToken(), "")
}

Method TestMalformedAuthorizationHeaderYieldsEmptyToken()
{
    Kill %request
    Set %request = ##class(%CSP.Request).%New()
    Set %request.CgiEnvs("HTTP_AUTHORIZATION") = "Basic dXNlcjpwYXNz"
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).ExtractBearerToken(), "")
}

Method TestWellFormedBearerHeaderIsExtracted()
{
    Kill %request
    Set %request = ##class(%CSP.Request).%New()
    Set %request.CgiEnvs("HTTP_AUTHORIZATION") = "Bearer abc123"
    Do $$$AssertEquals(##class(sentai.rest.Dispatcher).ExtractBearerToken(), "abc123")
}

}
