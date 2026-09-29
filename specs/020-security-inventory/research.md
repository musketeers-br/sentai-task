# Research: Security Inventory (spec 020)

Probed on 2026-09-29 against the dev primary (IRIS 2026.2, `_SYSTEM`), read-only, plus one
temporary x509 credential (public certificate only, self-signed, 10 days) created in `%SYS` to see
a populated answer and deleted right after. No secret value was printed or kept. The route list
comes from the compiled URL map of `%Api.Admin.Dispatch.v2`.

## R-1 Endpoints and what they return

| Read | Route (GET) | Answer (fields) | Dev instance |
|---|---|---|---|
| Roles | `/api/admin/v2/security/roles` | `Name, Description, CreatedBy, EscalationOnly` — **no resources** | 43 |
| One role | `/api/admin/v2/security/role?name=` | `Description, EscalationOnly, GrantedRoles[], Resources[{Name, Permissions}]` | — |
| Role owners | `/api/admin/v2/security/role/owners?name=` | `[{Name, Type (User/Role), AdminOption}]` | `%All`: 8 |
| Resources | `/api/admin/v2/security/resources` | `Name, Description, PublicPermission, ResourceType, AllowDelete` | 136 |
| SSL/TLS configs | `/api/admin/v2/security/ssl-configurations` | `Name, Description, Enabled, Type` | 4 (all clients) |
| One SSL/TLS config | `/api/admin/v2/security/ssl-configuration?name=` | `CertificateFile, CAFile, CAPath, PrivateKeyFile, PrivateKeyType, TLSMinVersion, TLSMaxVersion, VerifyPeer, Enabled, Type, CipherList, Ciphersuites, OCSP…` — **file paths, no validity** | all 4 have no certificate file |
| x509 credentials | `/api/admin/v2/security/x509-credentials` | `Alias, OwnerList, PeerNames, HasPrivateKey (bool), CAFile` | 0 |
| One credential's certificate | `/api/admin/v2/security/x509-credential/certificate?alias=` | `SubjectDN, IssuerDN, SerialNumber, ValidityNotBefore, ValidityNotAfter ("YYYY-MM-DD hh:mm:ss"), HasPrivateKey` | probe: NotAfter = created + 10 days |
| OAuth server | `/api/admin/v2/security/oauth2/server` | **404** `ERROR #8864: OAuth 2.0 server is not configured.` (`id: OAuth2NoConfiguration`) | not configured |
| Server's clients | `/api/admin/v2/security/oauth2/server/clients` | list | 0 |
| Server definitions (client side) | `/api/admin/v2/security/oauth2/client/server-definitions` | list | 0 |
| Client configurations | `/api/admin/v2/security/oauth2/client/client-configurations?serverId=` | **400** `ERROR #40300 … 'serverId' is required` without it | — |
| Resource servers | `/api/admin/v2/security/oauth2/resource-servers` | list | 0 |

Note: the paths the team's review named (`/security/oauth2/server-definitions`,
`/security/oauth2/client-configurations`) answer 404 with an empty body; the real ones are under
`/security/oauth2/client/…`.

- **Decision**: use exactly these routes. Roles need one read per role (N = 43 on dev); the
  x509 validity needs one read per credential.
- **Rationale**: the list answers omit what the rules need (resources per role, validity).
- **Alternatives considered**: reading `Security.Roles` / `%SYS.X509Credentials` in-process —
  rejected by Constitution III (the platform must decide each read with the run's credential, and
  a target server is only reachable through its API).

## R-2 Certificate validity — where it exists

- **Decision**: validity is read **only** from `x509-credential/certificate` (`ValidityNotAfter`).
  SSL/TLS configurations are listed with their certificate file *path* and "validity not reported
  by the platform" (*info*) when they name a file; when a configuration names no file (all four on
  the dev instance), it is listed without a certificate.
- **Rationale**: the platform exposes no validity for configuration files; opening those files
  from the product would bypass the platform (Constitution III) and fails on a target server.
  x509 credentials are the platform's registry of certificates and do report validity.
- **Consequence (documented deviation)**: a certificate used only as an SSL/TLS configuration file,
  and not registered as an x509 credential, is not checked for expiry. The README says so and
  suggests registering it as a credential. This is the "platform deviation" of the spec's
  assumptions, recorded in the style of spec 001's compatibility statement.
- **Alternatives considered**: matching configuration file paths to credentials — the credential
  answer has no file path, so there is nothing to match on.

## R-3 OAuth "not configured" and the serverId requirement

- **Decision**: `oauth-inventory` reads the server; a 404 whose status error `id` is
  `OAuth2NoConfiguration` (code 8864) is the **not-configured** state for the server part (not a
  refusal, not a failure). It then reads server definitions and, **per definition**,
  `client-configurations?serverId=<definition id>`; resource servers are read regardless. The
  step completes with `configured: false` when the server is not configured and all lists are
  empty.
- **Rationale**: spec FR-008 and edge case "OAuth reads that need a server id".
- **Resolved (T001)**: a definition's `ID` is passed as `serverId`; the per-client detail read
  also needs `applicationName`. See [evidence/t001-security-reads.md](evidence/t001-security-reads.md).

## R-4 Privileges

- **Decision**: no privilege table in the product. T001 confirmed: an account with the demo
  resources (no `%Admin_Secure`) gets 403 on every route used; `_SYSTEM` reads them all on both
  instances. The README states the observation.
- **Consequence**: on the public demo (account without `%Admin_Secure`) the three steps fail with
  the platform's 403, verbatim — the same as `security-posture-report` today. The README says so.

## R-5 Read budget and time

- Roles: 1 + 43 reads; resources 1; certificates 1 + 4 (configs) + N credentials; OAuth up to
  4 + D definitions. About 20 ms per local read (spec 013 R-3) → under 2 s per step on dev.
- **Decision**: cap per-item reads at 200 (roles, credentials, configurations, definitions), as
  spec 013 caps users; items beyond the cap are counted in `itemsOmitted` and raise an *info*
  finding `NOT_ALL_READ`.

## R-6 Resource families for severity (FR-007)

- **Decision**: *database* = names starting `%DB_`; *administration* = `%Admin_`;
  *development* = `%Development`. A public permission containing `W` or `U` on these is *high*;
  on any other resource it is *medium*. `R` alone is not a finding (the platform ships several
  resources publicly readable, such as `%DB_IRISLIB`… T001 lists the dev instance's public
  permissions for the evidence).
- **All-powerful role**: `%All`. A role other than `%All` whose `GrantedRoles` contains `%All` is
  *high* (`ROLE_GRANTS_ALL`). Holders of `%All` (users) are already reported by spec 013's
  security posture; `role/owners` is not needed.

## R-7 Test fixtures

- **Decision**: backend tests script the answers with `AdminApiDouble` (as spec 013). e2e and
  acceptance create, on the dev stack only, an x509 credential from a throw-away self-signed
  certificate (`openssl req -x509 -days 10`, the key deleted immediately, never loaded), in `%SYS`
  through `iris session`, named `sentai-e2e-020-*`, and delete it afterwards; the same on
  `iris-target` for the remote case. No OAuth fixture in e2e (R-3 decides after T001).
