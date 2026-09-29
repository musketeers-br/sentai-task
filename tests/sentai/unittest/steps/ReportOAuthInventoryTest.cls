/// Spec 020 US3 (FR-008): the OAuth inventory over scripted platform answers (field names from
/// evidence t001 (2)).
Class sentai.unittest.steps.ReportOAuthInventoryTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Script(path As %String, result, status As %Integer = 200)
{
    Do ##class(sentai.unittest.steps.ReportCertificateExpiryTest).Script("oauth2/"_path, result, status)
}

ClassMethod Build(params As %DynamicObject = "", Output report As %DynamicObject) As %Status
{
    Set:(params = "") params = {}
    Quit ##class(sentai.dispatch.ReadExecutor).Build("oauth-inventory", params, ##class(sentai.steps.reports.Reader).For("", "tok"), .report)
}

ClassMethod ScriptNotConfigured()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/security/oauth2/server", "GET", 404, "", {"status": {"errors": [{"error": "ERROR #8864: OAuth 2.0 server is not configured.", "code": 8864, "domain": "%ObjectErrors", "id": "OAuth2NoConfiguration"}], "summary": "ERROR #8864: OAuth 2.0 server is not configured."}}.%ToJSON())
    Do ..Script("server/clients", [])
    Do ..Script("client/server-definitions", [])
    Do ..Script("resource-servers", [])
}

ClassMethod Rules(report As %DynamicObject) As %String
{
    Quit ##class(sentai.unittest.steps.ReportCertificateExpiryTest).Rules(report)
}

Method TestNotConfiguredCompletes()
{
    Do ..ScriptNotConfigured()
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertEquals(report.details.configured, 0)
    Do $$$AssertEquals(report.details.serverMessage, "ERROR #8864: OAuth 2.0 server is not configured.")
    Do $$$AssertEquals(report.findings.%Size(), 0)
}

Method TestClientSideReadPerServerDefinition()
{
    Do ..ScriptNotConfigured()
    Do ..Script("client/server-definitions", [{"ID": 1, "IssuerEndpoint": "https://issuer.example/oauth2", "ClientCount": 2, "ResourceCount": 0}])
    Do ..Script("client/server-definition?serverId=1", {"IssuerEndpoint": "https://issuer.example/oauth2", "SSLConfiguration": "X", "ServerCredentials": "must-not-leak", "Metadata": {"authorization_endpoint": "https://issuer.example/oauth2/authorize", "token_endpoint": "http://issuer.example/oauth2/token"}})
    Do ..Script("client/client-configurations?serverId=1", [{"ApplicationName": "app", "ClientType": "confidential", "DefaultScope": ""}, {"ApplicationName": "local", "ClientType": "public"}])
    Do ..Script("client/client-configuration?serverId=1&applicationName=app", {"ServerDefinition": "1", "Enabled": true, "ClientType": "confidential", "RedirectionEndpoint": "http://app.example/cb", "ClientId": "must-not-leak", "ClientSecret": "must-not-leak", "ClientCredentials": "must-not-leak", "Metadata": {"grant_types": ["authorization_code", "password"]}})
    Do ..Script("client/client-configuration?serverId=1&applicationName=local", {"ServerDefinition": "1", "Enabled": false, "ClientType": "public", "RedirectionEndpoint": "http://localhost:52773/csp/sys", "Metadata": {}})
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertEquals(report.details.configured, 1)
    Do $$$AssertEquals(report.details.serverDefinitions.%Size(), 1)
    Do $$$AssertEquals(report.details.serverDefinitions.%Get(0).tokenEndpoint, "http://issuer.example/oauth2/token")
    Do $$$AssertEquals(report.details.clientConfigurations.%Size(), 2)
    Set app = report.details.clientConfigurations.%Get(0)
    Do $$$AssertEquals(app.name, "app")
    Do $$$AssertEquals(app.redirectURL, "http://app.example/cb")
    Set rules = ..Rules(report)
    Do $$$AssertTrue(rules [ "OAUTH_PASSWORD_GRANT:client configuration app,", rules)
    Do $$$AssertTrue(rules [ "OAUTH_NON_HTTPS_ADDRESS:client configuration app,", rules)
    Do $$$AssertTrue(rules [ "OAUTH_NON_HTTPS_ADDRESS:server definition 1,", "the http token endpoint")
    Do $$$AssertNotTrue(rules [ "client configuration local,", "loopback redirect is not a finding")
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak", "no client secret, client id or credential name is ever copied")
}

Method TestServerConfiguredWithClients()
{
    Do ..ScriptNotConfigured()
    Do ..Script("server", {"IssuerEndpoint": "https://this.example/oauth2", "SupportedGrantTypes": "authorization_code,password"})
    Do ..Script("server/clients", [{"Name": "portal", "ClientType": "confidential", "RedirectURL": "https://portal.example/cb", "SupportedGrantTypes": "password", "ClientSecret": "must-not-leak"}])
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertEquals(report.details.configured, 1)
    Do $$$AssertEquals(report.details.server.issuer, "https://this.example/oauth2")
    Do $$$AssertTrue(..Rules(report) [ "OAUTH_PASSWORD_GRANT:server client portal,")
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak")
}

Method TestRefusals()
{
    Do ..ScriptNotConfigured()
    Do ..Script("resource-servers", "ERROR #822: Access Denied", 403)
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertTrue(..Rules(report) [ "INCOMPLETE_READ:OAuth resource servers,")

    For path = "server", "server/clients", "client/server-definitions", "resource-servers" {
        Do ..Script(path, "ERROR #822: Access Denied", 403)
    }
    Set sc = ..Build(, .report)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "returned HTTP 403: ERROR #822: Access Denied")
}

}
