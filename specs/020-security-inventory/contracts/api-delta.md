# API delta: Security Inventory (spec 020)

Changes to `specs/002-canvas-ui/contracts/openapi.yaml`: **values only**, no new route.

## `GET /catalog/step-types`

Three new entries (all `available: true`, `remoteCapable: true`, `executor: "platform-read"`,
`category: "security"`, `destructive: false`, `pausable: false`):

```json
{ "type": "certificate-expiry-check", "label": "Certificate expiry check",
  "class": "sentai.steps.reports.CertificateExpiry",
  "parameters": [ { "name": "warnDays", "property": "WarnDays", "type": "integer", "required": false,
                    "default": 30, "min": 1, "max": 365,
                    "description": "Fail when a certificate expires within this many days (or has expired)" } ] }
{ "type": "permissions-inventory", "label": "Permissions inventory",
  "class": "sentai.steps.reports.PermissionsInventory",
  "parameters": [ { "name": "failOnFindings", "property": "FailOnFindings", "type": "boolean", "required": false, "default": false,
                    "description": "Fail the step when any high finding exists" } ] }
{ "type": "oauth-inventory", "label": "OAuth inventory",
  "class": "sentai.steps.reports.OAuthInventory",
  "parameters": [ { "name": "failOnFindings", "property": "FailOnFindings", "type": "boolean", "required": false, "default": false,
                    "description": "Fail the step when any high finding exists" } ] }
```

## Validation (`POST /flows/{id}/validate`, dispatch, schedule)

Existing codes apply: `PARAM_TYPE_MISMATCH`, `PARAM_OUT_OF_RANGE` (e.g. `warnDays: 0` or `400`),
`PARAM_UNKNOWN`. No new code.

## Step results (`GET /runs/{guid}` → `steps[].result`)

The report shapes of [data-model.md](../data-model.md). `failureReason` of a failed
`certificate-expiry-check` is
`"<n> certificate(s) expired or expiring within <warnDays> days: <alias> (<notAfter>); …"`.

## Platform routes read (management API v2, GET only)

`security/roles`, `security/role?name=`, `security/resources`, `security/ssl-configurations`,
`security/ssl-configuration?name=`, `security/x509-credentials`,
`security/x509-credential/certificate?alias=`, `security/oauth2/server`,
`security/oauth2/server/clients`, `security/oauth2/client/server-definitions`,
`security/oauth2/client/client-configurations?serverId=`, `security/oauth2/resource-servers`.
