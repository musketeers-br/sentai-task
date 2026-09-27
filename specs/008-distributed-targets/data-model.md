# Data Model — 008 Distributed Targets

## Target (new, persistent: `sentai.model.Target`)

| Property | Type | Rule |
|---|---|---|
| `name` | string ≤ 64, unique index | `^[A-Za-z0-9][A-Za-z0-9._-]*$`; the key in every API path |
| `baseUrl` | string ≤ 256 | `scheme://host:port`, no path, no credentials, no query; `http` only for loopback or with the dev allowance (FR-003, R-11) |
| `description` | string ≤ 512 | optional |
| `online` | boolean, default true | set only through `POST /targets/{name}/online` (FR-004) |
| `createdAt`, `updatedAt` | timestamp | |
| `createdBy`, `updatedBy` | string | the signed-in operator |

No credential field exists, by construction (FR-002).

## Step (existing): `target`

| Property | Type | Rule |
|---|---|---|
| `target` | string ≤ 64, optional | absent / `""` = local. A name only: never resolved at save time, so a flow saves even if the target is later renamed or deleted (then `TARGET_NOT_FOUND` at validation) |

## StepRun (existing): where it ran

| Property | Type | Rule |
|---|---|---|
| `executedOn` | string ≤ 64 | `"local"` or the target name; set when the step starts |
| `targetBaseUrl` | string ≤ 256 | the address used, frozen at start (FR-018); `""` for local |
| `executedAs` | (existing) | for a remote step, the `sub` of the target credential |
| `adminJobId` | (existing) | the `Location` path; for a remote step it is relative to `targetBaseUrl` |
| `result` | (existing) | now also filled for platform-executed steps (R-10) |

## Run target credential (transient, IRISTEMP)

`^IRIS.Temp.sentaiTargetCred(runGuid, targetName) = $lb(accessToken, refreshToken, issuedAt, sub)`
`^IRIS.Temp.sentaiTargetCred(runGuid, "lastError", stepRunGuid) = <transport error text>`

Written at dispatch after redemption; renewed by the run loop after 40 s (same rule as E-1); killed
by `FinalizeRun` with the local credential. Never returned by any API.

## Target status (computed per request, never stored)

```
{ "target": "iris-target", "readAt": "<primary time>",
  "reachable": true, "version": "<info.serverVersion>", "user": "<info.username>",
  "categories": [ <each wqm-categories entry verbatim> ],
  "unreachable": null | { "transportError": "<text>" },
  "refused": null | { "httpStatus": 401, "detail": "<errors joined>", "platformStatus": {…} } }
```

`queueLength` appears per category only if R-2 is proven.

## Step-type catalog entry (existing): `remoteCapable`

`remoteCapable = (executor = "platform-api") && (type ≠ "custom")`, computed in
`sentai.registry.StepType`, returned by `GET /catalog/step-types` (FR-008). In v1 this makes
`integrity-check` the one available remote-capable type.

## Validation findings (new codes)

| Code | Level | When | Extra fields |
|---|---|---|---|
| `TARGET_NOT_FOUND` | error | `target` names no registered target | `stepId`, `target` |
| `TARGET_OFFLINE` | error | target `online = false` | `stepId`, `target` |
| `STEP_TYPE_NOT_REMOTE_CAPABLE` | error | type not `remoteCapable` | `stepId`, `target` |
| `TARGET_UNREACHABLE` | error | no HTTP answer from `GET {base}/api/admin/info` | `stepId`, `target`, message = transport error verbatim |
| `TARGET_REFUSED` | error | the target answered 4xx to that read | `stepId`, `target`, message = its status + errors verbatim (deviation D-4) |
| `NAMESPACE_NOT_FOUND` | error (existing) | namespace absent from the target's `info.namespaces` | `stepId` |
| `TARGET_NOT_VERIFIED` | warning | validate without a credential for that target (R-8) | `stepId`, `target` |

Dispatch refusals (HTTP problem, no run created): `TARGET_CREDENTIAL_MISSING` (400, names the target
and its steps) and `TARGET_CREDENTIAL_USER_MISMATCH` (403, names the target and both users).
