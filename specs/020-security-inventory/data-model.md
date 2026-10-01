# Data Model: Security Inventory (spec 020)

No new persistent class. Each step stores its report as `StepRun.result` (spec 005/013
`FitResult(json, "summary,findings")`). Shape common to the three types (spec 013 D-4):

```json
{ "type": "<type>", "instance": "local|<target>",
  "summary": { "high": 0, "medium": 0, "info": 0, "itemsRead": 0, "itemsOmitted": 0, "asOf": "YYYY-MM-DD hh:mm:ss" },
  "findings": [ { "severity": "high|medium|info", "rule": "RULE_ID", "item": "…", "detail": "…" } ],
  "details": { … } }
```

`asOf` (new, optional in the shared shape) is the instance's date and time used for "days left".

## 1. `certificate-expiry-check`

Parameters: `warnDays` integer, 1–365, default 30.

```json
"details": {
  "credentials": [ { "alias": "…", "subject": "CN=…", "issuer": "CN=…", "serial": "…",
                     "notBefore": "…", "notAfter": "…", "daysLeft": 10, "hasPrivateKey": false,
                     "status": "expired|expiring|valid|unknown" } ],
  "configurations": [ { "name": "…", "type": "client|server", "enabled": true,
                        "certificateFile": "/path or empty", "caFile": "…",
                        "tlsMin": 16, "tlsMax": 32, "verifyPeer": 0,
                        "validity": "not reported by the platform" } ] }
```

Allow-lists: credentials `Alias, OwnerList, PeerNames, HasPrivateKey` + certificate `SubjectDN,
IssuerDN, SerialNumber, ValidityNotBefore, ValidityNotAfter`; configurations `Name, Description,
Enabled, Type, CertificateFile, CAFile, TLSMinVersion, TLSMaxVersion, VerifyPeer`. Never copied:
`PrivateKeyFile`, `PrivateKeyType`, `PrivateKeyPassword` or any other field.

`daysLeft` = whole days from `asOf` to `notAfter` (negative when expired).

| Rule | Severity | When |
|---|---|---|
| `CERT_EXPIRED` | high | `daysLeft < 0` |
| `CERT_EXPIRING` | medium | `0 ≤ daysLeft ≤ warnDays` |
| `CERT_VALIDITY_UNKNOWN` | info | a credential whose certificate read gives no `ValidityNotAfter` |
| `CONFIG_VALIDITY_NOT_REPORTED` | info | a configuration naming a certificate file (R-2) |
| `INCOMPLETE_READ` | medium | one read refused while another succeeded (text verbatim) |
| `NOT_ALL_READ` | info | items beyond the 200 cap |

Outcome: fails when `CERT_EXPIRED + CERT_EXPIRING > 0`, reason
`"<n> certificate(s) expired or expiring within <warnDays> days: <alias> (<notAfter>); …"`
(first 5). Fails on reads only when every read was refused (platform text).

## 2. `permissions-inventory`

Parameters: `failOnFindings` boolean, default false.

```json
"details": {
  "roles": [ { "name": "…", "description": "…", "escalationOnly": false,
               "resources": [ { "name": "%DB_USER", "permissions": "RW" } ], "grantedRoles": [] } ],
  "resources": [ { "name": "…", "type": "System|Application|…", "publicPermission": "R" } ] }
```

| Rule | Severity | When |
|---|---|---|
| `PUBLIC_WRITE_OR_USE_SENSITIVE` | high | `publicPermission` has `W` or `U` and the name starts `%DB_`, `%Admin_` or is `%Development` |
| `PUBLIC_WRITE_OR_USE` | medium | `publicPermission` has `W` or `U` on any other resource |
| `ROLE_GRANTS_ALL` | high | a role other than `%All` whose `grantedRoles` includes `%All` |
| `INCOMPLETE_READ`, `NOT_ALL_READ` | as above | |

Outcome: completes; fails only when `failOnFindings` and `high > 0` (spec 013 D-6 text).

## 3. `oauth-inventory`

Parameters: `failOnFindings` boolean, default false.

```json
"details": {
  "configured": false,
  "serverMessage": "ERROR #8864: OAuth 2.0 server is not configured.",
  "server": null | { "issuer": "…", "enabled": true, "grantTypes": ["…"] },
  "serverClients": [ { "name": "…", "clientType": "…", "grantTypes": ["…"], "redirectURLs": ["…"] } ],
  "serverDefinitions": [ { "id": 1, "issuer": "https://…", "clientCount": 1, "resourceCount": 0,
                           "authorizationEndpoint": "https://…", "tokenEndpoint": "https://…" } ],
  "clientConfigurations": [ { "serverId": 1, "name": "<ApplicationName>", "clientType": "confidential",
                              "enabled": true, "redirectURL": "<RedirectionEndpoint>", "grantTypes": [] } ],
  "resourceServers": [ { "name": "…", "serverId": "…" } ] }
```

Field names confirmed in T001 (client side); server-side client fields could not be observed (no
OAuth server on either instance) and are copied only from the allow-list `Name, Description,
ClientType, RedirectURL, SupportedGrantTypes`. Never copied: `ClientSecret`, `ClientId`,
`ClientCredentials`, `ServerCredentials`, key material.

| Rule | Severity | When |
|---|---|---|
| `OAUTH_PASSWORD_GRANT` | medium | a server client or client configuration allowing the resource-owner password grant |
| `OAUTH_NON_HTTPS_ADDRESS` | medium | an issuer, redirect or endpoint address that is not `https://`, except loopback |
| `INCOMPLETE_READ`, `NOT_ALL_READ` | as above | |

Not configured (server 404 with id `OAuth2NoConfiguration`) is `configured: false`, the message
kept verbatim, no finding. Outcome as `permissions-inventory`.

## 4. Registry entries

| type | label | category | executor | destructive | parameters |
|---|---|---|---|---|---|
| `certificate-expiry-check` | Certificate expiry check | security | platform-read | no | `warnDays` integer 1–365 default 30 |
| `permissions-inventory` | Permissions inventory | security | platform-read | no | `failOnFindings` boolean default false |
| `oauth-inventory` | OAuth inventory | security | platform-read | no | `failOnFindings` boolean default false |

All `available: true`, `remoteCapable: true` (derived for `platform-read`, spec 013), schedulable
(not destructive, spec 015).
