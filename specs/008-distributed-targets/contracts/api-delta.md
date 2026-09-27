# API Contract Delta — 008 Distributed Targets

Base: `/csp/sentai/api/v1`, same authentication as today (primary bearer token on every call).
All errors use the existing Problem shape `{status, title, detail}`; target refusals add
`platformStatus` verbatim, as spec 006 does. Spec 009 builds on this file.

## Targets

### `GET /targets` → 200
`[ { "name", "baseUrl", "description", "online", "createdAt", "updatedAt" } ]`, ordered by name.

### `POST /targets` → 201 `{target}`
Body `{ "name", "baseUrl", "description"? }`.
- 400 `INVALID_TARGET: …` — name pattern, malformed URL, URL with a path/userinfo/query.
- 400 `INSECURE_TARGET: http is allowed only for loopback targets unless the development allowance is set`.
- 409 `TARGET_EXISTS`.

### `GET /targets/{name}` → 200 `{target}` · 404 `TARGET_NOT_FOUND`
### `PUT /targets/{name}` → 200 `{target}`
Body `{ "baseUrl", "description" }` (the name is the key and cannot change; `online` is not
accepted here). Same 400s as POST; 404.
### `DELETE /targets/{name}` → 204 · 404
Allowed while flows reference it (they then fail validation with `TARGET_NOT_FOUND`); running runs
keep their frozen address.

### `POST /targets/{name}/online` → 200 `{target}`
Body `{ "online": true | false }`; 400 when not a boolean.

### `POST /targets/{name}/sign-in` → 200
Body `{ "user", "password" }` → the target's own pair, nothing kept:
`{ "target", "accessToken", "refreshToken", "sub", "expiresIn" }`.
- 401/403 from the target → same status, `detail` = the target's `errors[].error` joined (or `""`),
  `platformStatus` verbatim.
- no HTTP answer → 502 `TARGET_UNREACHABLE: <transport error verbatim>`.
- 409 `TARGET_OFFLINE`.

### `GET /targets/{name}/status` → 200
Header `X-Sentai-Target-Authorization: Bearer <target access token>`. Body as data-model §Target
status. Unreachable and refused are **200 with the fields set** (the read happened; the target
answered or not). 400 when the header is missing.

## Flows

### Step shape
Optional `"target": "<name>"`; absent or `""` = local. Returned by every flow read.

### `POST /flows/{id}/validate`
Optional body `{ "targetCredentials": [ { "target", "accessToken" } ] }`. New findings: data-model
§Validation findings.

### `POST /flows/{id}/dispatch`
Body gains `"targetCredentials": [ { "target", "refreshToken" } ]`, one per distinct target used.
Checked before validation, and before any run exists:
- a target used by a step without an entry → 400 `TARGET_CREDENTIAL_MISSING: target '<t>' (steps 03)`;
- redemption refused → the target's status, `detail` verbatim, `platformStatus`;
- redeemed `sub` ≠ dispatching user → 403 `TARGET_CREDENTIAL_USER_MISMATCH: the credential for target '<t>' belongs to '<sub>', not to '<user>'`;
- no HTTP answer → 502 `TARGET_UNREACHABLE: target '<t>': <transport error verbatim>`.

Then validation runs with the redeemed tokens (422 on errors), then confirmations (428), then 202.

## Runs

`steps[]` gains `"executedOn": "local" | "<target name>"`. `result` is now also present for
platform-executed steps (the async-result `result` object, fitted). Live events are unchanged.
Cancel / pause of a remote step are forwarded to its target (`async-result/cancel|pause?id=`); a
refusal there is recorded as the step's failure reason verbatim.

## Catalog

`GET /catalog/step-types` entries gain `"remoteCapable": true | false`.

## Management API consumed on each target (IRIS 2026.2, spec 001 evidence)

| Purpose | Call |
|---|---|
| Sign-in | `POST /api/admin/login` (Basic) — ev. 01 |
| Renew | `POST /api/admin/refresh` `{refresh_token}` — ev. 02 |
| Identity, version, namespaces | `GET /api/admin/info` — ev. 00 |
| Categories | `GET /api/admin/v2/wqm-categories` — ev. 09 |
| Start integrity check | `POST /api/admin/v2/database-dir/integrity-check` `{}` — ev. 06 |
| Poll | `GET /api/admin/v1/async-result?id=` — ev. 07 |
| Pause / cancel | `POST /api/admin/v2/async-result/{pause|cancel}?id=` — ev. 08 |
