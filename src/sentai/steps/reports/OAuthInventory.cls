/// Spec 020 US3 (`oauth-inventory`, FR-008): the instance's OAuth 2.0 configuration — this
/// instance as an authorization server (and its clients), the server definitions it trusts as a
/// client (and their client configurations, read per definition: the platform requires `serverId`),
/// and its resource servers. The platform's `OAuth2NoConfiguration` (ERROR #8864) is the
/// *not configured* state, not a refusal (plan D-5). Rules: a client allowing the resource-owner
/// password grant, and a non-https address (loopback excepted), are *medium*. Never copied:
/// client secrets, client ids, credential names or key material (evidence t001 (2)).
Class sentai.steps.reports.OAuthInventory Extends sentai.steps.reports.Report
{

Parameter P = "/api/admin/v2/security/oauth2/";

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("oauth-inventory")
    Set details = {"configured": false, "serverMessage": "", "server": null, "serverClients": [], "serverDefinitions": [], "clientConfigurations": [], "resourceServers": []}
    Set reads = 0, refused = 0, firstProblem = ""

    // This instance as an authorization server.
    Set reads = reads + 1
    Set server = reader.Get(..#P_"server", .problem, .errorId)
    If (errorId = "OAuth2NoConfiguration") || (problem [ "#8864") {
        Set details.serverMessage = $S(problem [ ": ERROR":"ERROR"_$P(problem, ": ERROR", 2, *), 1:problem)
    } ElseIf (problem '= "") {
        Set refused = refused + 1, firstProblem = problem
        Do ..AddIncompleteRead(report, "OAuth server", problem)
    } Else {
        Set details.configured = 1
        Set s = ..Pick(server, $LB("IssuerEndpoint", "Description", "SupportedGrantTypes", "SupportedScopes"))
        Set details.server = {"issuer": (s.IssuerEndpoint), "description": (s.Description), "grantTypes": (..List(s.SupportedGrantTypes))}
        Do:..IsInsecureAddress(s.IssuerEndpoint) ..AddFinding(report, "medium", "OAUTH_NON_HTTPS_ADDRESS", "server", "issuer "_s.IssuerEndpoint_" is not https")
    }

    Set reads = reads + 1
    Set list = reader.Get(..#P_"server/clients", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = $S(firstProblem '= "":firstProblem, 1:problem)
        Do ..AddIncompleteRead(report, "OAuth server clients", problem)
    } Else {
        Set n = 0
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .c) {
            Set n = n + 1
            Continue:(n > ..#CAP)
            Set safe = ..Pick($S($IsObject(c):c, 1:{"Name": (c)}), $LB("Name", "Description", "ClientType", "RedirectURL", "SupportedGrantTypes"))
            Set item = {"name": (safe.Name), "description": (safe.Description), "clientType": (safe.ClientType), "redirectURLs": (..List(safe.RedirectURL)), "grantTypes": (..List(safe.SupportedGrantTypes))}
            Do details.serverClients.%Push(item)
            Do ..ClientRules(report, "server client "_item.name, item.grantTypes, item.redirectURLs)
        }
        Do:(n > ..#CAP) ..AddNotAllRead(report, "OAuth server clients", n - ..#CAP)
    }

    // This instance as a client: the servers it trusts and its client configurations per server.
    Set reads = reads + 1
    Set list = reader.Get(..#P_"client/server-definitions", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = $S(firstProblem '= "":firstProblem, 1:problem)
        Do ..AddIncompleteRead(report, "OAuth server definitions", problem)
    } Else {
        Set n = 0
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .d) {
            Set n = n + 1
            Continue:(n > ..#CAP)
            Do ..Definition(reader, report, details, $S($IsObject(d):d, 1:{"ID": (d)}))
        }
        Do:(n > ..#CAP) ..AddNotAllRead(report, "OAuth server definitions", n - ..#CAP)
    }

    Set reads = reads + 1
    Set list = reader.Get(..#P_"resource-servers", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = $S(firstProblem '= "":firstProblem, 1:problem)
        Do ..AddIncompleteRead(report, "OAuth resource servers", problem)
    } Else {
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .r) {
            Set safe = ..Pick($S($IsObject(r):r, 1:{"Name": (r)}), $LB("Name", "Description", "IssuerEndpoint", "ServerDefinition"))
            Do details.resourceServers.%Push({"name": (safe.Name), "description": (safe.Description), "issuer": (safe.IssuerEndpoint), "serverId": (safe.ServerDefinition)})
        }
    }

    Set:((details.serverDefinitions.%Size() + details.resourceServers.%Size()) > 0) details.configured = 1
    Do details.%Set("configured", ''details.configured, "boolean")
    Set report.details = details
    Set report.summary.itemsRead = reader.Reads
    Quit:(refused = reads) $$$ERROR($$$GeneralError, firstProblem)
    Quit:(parameters.failOnFindings && (report.summary.high > 0)) $$$ERROR($$$GeneralError, ..HighFindingsText(report))
    Quit $$$OK
}

/// A server definition, with its endpoints and its client configurations (evidence t001 (2)).
ClassMethod Definition(reader As sentai.steps.reports.Reader, report As %DynamicObject, details As %DynamicObject, entry As %DynamicObject)
{
    Set head = ..Pick(entry, $LB("ID", "IssuerEndpoint", "ClientCount", "ResourceCount"))
    Set id = head.ID
    Set def = {"id": (id), "issuer": (head.IssuerEndpoint), "clientCount": (head.ClientCount), "resourceCount": (head.ResourceCount), "authorizationEndpoint": "", "tokenEndpoint": ""}
    Do:..IsInsecureAddress(head.IssuerEndpoint) ..AddFinding(report, "medium", "OAUTH_NON_HTTPS_ADDRESS", "server definition "_id, "issuer "_head.IssuerEndpoint_" is not https")
    Set detail = reader.Get(..#P_"client/server-definition?serverId="_$ZCVT(id, "O", "URL"), .problem)
    If (problem '= "") {
        Do ..AddIncompleteRead(report, "server definition "_id, problem)
    } ElseIf $IsObject(detail) && $IsObject(detail.Metadata) {
        Set m = ..Pick(detail.Metadata, $LB("authorization_endpoint", "token_endpoint"))
        Set def.authorizationEndpoint = m."authorization_endpoint", def.tokenEndpoint = m."token_endpoint"
        For address = def.authorizationEndpoint, def.tokenEndpoint {
            Do:..IsInsecureAddress(address) ..AddFinding(report, "medium", "OAUTH_NON_HTTPS_ADDRESS", "server definition "_id, address_" is not https")
        }
    }
    Do details.serverDefinitions.%Push(def)

    Set clients = reader.Get(..#P_"client/client-configurations?serverId="_$ZCVT(id, "O", "URL"), .problem)
    If (problem '= "") {
        Do ..AddIncompleteRead(report, "client configurations of server definition "_id, problem)
        Quit
    }
    Set n = 0
    Set it = $S($IsObject(clients):clients.%GetIterator(), 1:"")
    While $IsObject(it) && it.%GetNext(.k, .c) {
        Set n = n + 1
        Continue:(n > ..#CAP)
        Set name = $S($IsObject(c):c.ApplicationName, 1:c)
        Set item = {"serverId": (id), "name": (name), "clientType": ($S($IsObject(c):c.ClientType, 1:"")), "enabled": "", "redirectURL": "", "grantTypes": []}
        Set one = reader.Get(..#P_"client/client-configuration?serverId="_$ZCVT(id, "O", "URL")_"&applicationName="_$ZCVT(name, "O", "URL"), .problem)
        If (problem '= "") {
            Do ..AddIncompleteRead(report, "client configuration "_name, problem)
        } Else {
            Set safe = ..Pick(one, $LB("ClientType", "Enabled", "RedirectionEndpoint", "Metadata"))
            Set item.clientType = safe.ClientType, item.redirectURL = safe.RedirectionEndpoint
            Do item.%Set("enabled", ''safe.Enabled, "boolean")
            Set:$IsObject(safe.Metadata) item.grantTypes = ..List(safe.Metadata."grant_types")
            Do ..ClientRules(report, "client configuration "_name, item.grantTypes, ..List(item.redirectURL))
        }
        Do details.clientConfigurations.%Push(item)
    }
    Do:(n > ..#CAP) ..AddNotAllRead(report, "client configurations of server definition "_id, n - ..#CAP)
}

ClassMethod ClientRules(report As %DynamicObject, item As %String, grantTypes As %DynamicArray, addresses As %DynamicArray)
{
    Do:..Includes(grantTypes, "password") ..AddFinding(report, "medium", "OAUTH_PASSWORD_GRANT", item, "allows the resource-owner password grant")
    Set it = addresses.%GetIterator()
    While it.%GetNext(.k, .a) {
        Do:..IsInsecureAddress(a) ..AddFinding(report, "medium", "OAUTH_NON_HTTPS_ADDRESS", item, a_" is not https")
    }
}

/// A platform value as a JSON array of strings: an array as is, a string split on commas, else [].
ClassMethod List(value) As %DynamicArray
{
    Quit:$IsObject(value) value
    Set out = []
    For i = 1:1:$L(value, ",") { Set v = $ZSTRIP($P(value, ",", i), "<>W")  Do:(v '= "") out.%Push(v) }
    Quit out
}

}
