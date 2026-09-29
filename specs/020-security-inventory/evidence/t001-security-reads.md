# T001 — Security reads spike (2026-09-29, dev stack, IRIS 2026.2)

No secret value, key material, password or token is recorded here. Every object the spike created
(an x509 credential from a throw-away public certificate, an OAuth server definition and client
configuration, a temporary account and role) was deleted afterwards.

## (1) Routes, primary and iris-target

| Route (GET, v2) | Primary (`_SYSTEM`) | iris-target (`_SYSTEM`) |
|---|---|---|
| `security/roles` | 200, 43 | 200, 37 |
| `security/role?name=` | 200 `Description, EscalationOnly, GrantedRoles, Resources[{Name, Permissions}]` | 200 |
| `security/resources` | 200, 136 | 200, 131 |
| `security/ssl-configurations` | 200, 4 (all clients, no certificate file) | 200, 1 |
| `security/ssl-configuration?name=` | 200 (file paths, TLS versions, no validity) | 404 `ERROR #979` for a missing name |
| `security/x509-credentials` | 200, 0 (1 with the fixture: `Alias, OwnerList, PeerNames, HasPrivateKey, CAFile`) | 200, 0 |
| `security/x509-credential/certificate?alias=` | 200 `SubjectDN, IssuerDN, SerialNumber, ValidityNotBefore, ValidityNotAfter, HasPrivateKey` | — |
| `security/oauth2/server` | 404 `ERROR #8864: OAuth 2.0 server is not configured.` (`id: OAuth2NoConfiguration`) | same |
| `security/oauth2/server/clients` | 200, 0 | 200, 0 |
| `security/oauth2/client/server-definitions` | 200, 0 (1 with the fixture: `ID, IssuerEndpoint, ClientCount, ResourceCount`) | 200, 0 |
| `security/oauth2/client/server-definition?serverId=` | 200 `IssuerEndpoint, SSLConfiguration, ServerCredentials, Metadata{authorization_endpoint, token_endpoint}` | — |
| `security/oauth2/client/client-configurations?serverId=` | 200 `ApplicationName, ClientType, DefaultScope` | — |
| `security/oauth2/client/client-configuration?serverId=&applicationName=` | 200 `ServerDefinition, Enabled, Description, ClientType, SSLConfiguration, RedirectionEndpoint, JWTAudience, JWTInterval, ClientId, ClientCredentials, Metadata{…}, DefaultScope` | — |
| `security/oauth2/resource-servers` | 200, 0 | 200, 0 |

## (2) OAuth client side (stop condition not hit)

Client configurations are read per server definition: the definition list gives `ID`, which is
passed as `serverId`. The per-client read needs `applicationName`. The client answer carries no
client secret field; `ClientId` and `ClientCredentials` (the name of an x509 credential) are not
copied either (allow-list: `ApplicationName, ClientType, Enabled, Description, RedirectionEndpoint,
SSLConfiguration, DefaultScope, Metadata.grant_types`). Grant types inserted on the client's
metadata were not returned in `Metadata`; the password-grant rule therefore applies only when the
platform reports `grant_types` (documented). Server-side client fields (`server/clients`) could not
be observed because the OAuth server is not configured on either instance; the report copies
`Name, Description, ClientType, RedirectURL, SupportedGrantTypes` when present.

## (3) Demo-level account

A temporary account with the spec 011 demo resources (`%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW,
%Admin_Manage:U, %DB_IRISSYS:RW, %Admin_Operate:U`, no `%Admin_Secure`) gets **403** on every
route above, with an empty status summary. On the public demo the three steps therefore fail with
the platform's 403, as `security-posture-report` does.

## (4) Reader and the error id

`Reader.Get` returns only the problem text, not the platform's status error `id`. T006 adds an
optional `errorId` output so `oauth-inventory` recognises `OAuth2NoConfiguration` exactly.

## (5) Privileges per route (found by the acceptance run)

A run-as account with the demo resources plus `%Admin_Secure:U` reads roles, resources, SSL/TLS
configurations, x509 credentials and OAuth resource servers, but gets **403** on
`oauth2/server`, `oauth2/server/clients` and `oauth2/client/server-definitions`. Adding
`%Admin_OAuth2_Client:U` and `%Admin_OAuth2_Server:U` opens the server (then 404 #8864, not
configured) and the server definitions; `oauth2/server/clients` needs
`%Admin_OAuth2_Registration:U` (`%Admin_OAuth2_Server:RWU` alone is still refused). With the
partial set the OAuth step completed with `INCOMPLETE_READ` findings — the FR-011 behaviour.
