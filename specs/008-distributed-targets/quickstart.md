# Quickstart — 008 Distributed Targets (acceptance by curl)

Prerequisites: `docker compose up -d --build` (brings up `iris` and `iris-target`); the operator's
user exists on both with the same name. Credentials come only from `IRIS_USER` / `IRIS_PASSWORD`;
no token or password is written to any evidence file (status + body only, tokens redacted).

```sh
API=http://localhost:52773/csp/sentai/api/v1
TOK=$(curl -s -X POST -u "$IRIS_USER:$IRIS_PASSWORD" -H 'Content-Type: application/json' -d '{}' \
  http://localhost:52773/api/admin/login | jq -r .access_token)
H="Authorization: Bearer $TOK"
```

## (a) Register and read a target — US1, FR-001…FR-004

```sh
curl -s -X POST -H "$H" -d '{"name":"iris-target","baseUrl":"http://iris-target:52773","description":"demo"}' $API/targets
curl -s -H "$H" $API/targets
curl -s -X POST -H "$H" -d '{"name":"iris-target","baseUrl":"http://x:1"}' $API/targets      # 409
curl -s -X POST -H "$H" -d '{"name":"bad","baseUrl":"http://example.com:52773"}' $API/targets  # 400 INSECURE_TARGET without the allowance
```

## (b) Sign in and read status — FR-005, FR-006, FR-022

```sh
PAIR=$(curl -s -X POST -H "$H" -d "{\"user\":\"$IRIS_USER\",\"password\":\"$IRIS_PASSWORD\"}" $API/targets/iris-target/sign-in)
TT=$(echo "$PAIR" | jq -r .accessToken); TR=$(echo "$PAIR" | jq -r .refreshToken)
curl -s -H "$H" -H "X-Sentai-Target-Authorization: Bearer $TT" $API/targets/iris-target/status
```
Compare `version` and `categories` with the same reads made directly on the target (SC-006, < 3 s).
`docker stop sentai-task-iris-target-1`, read status again: `reachable:false`, transport error
verbatim. Start it again.

## (c) Refusals — US3

Seed flows with a step on `nope` (→ `TARGET_NOT_FOUND`), on the target set offline
(→ `TARGET_OFFLINE`), a `db-size-report` on the target (→ `STEP_TYPE_NOT_REMOTE_CAPABLE`); validate
without a target credential (→ warning `TARGET_NOT_VERIFIED`); dispatch without `targetCredentials`
(→ 400 `TARGET_CREDENTIAL_MISSING`); dispatch with another user's refresh token
(→ 403 `TARGET_CREDENTIAL_USER_MISMATCH`). Each answer is saved with its status.

## (d) The demo flow — US2, SC-001, SC-002

Flow: `01` integrity check (local), `02` integrity check (local), `03` integrity check on
`iris-target`, all three into `04` (local). Dispatch with `runCredential` (local, E-1) and
`targetCredentials:[{"target":"iris-target","refreshToken":"$TR"}]`. Follow `/runs/{guid}` until
terminal: `completed`, `executedOn` = local/local/iris-target/local, `executedAs` the operator on
each; `03.result` equals `GET {target}/api/admin/v1/async-result?id=<id>` read with a target token.

## (e) Target down mid-run — FR-016, SC-003

Same flow with step `03` timeout 1 min; stop `iris-target` once `03` is `running`. `03` fails after
about a minute with `timed out after 1 min; last transport error: …`; `01`, `02` complete; `04` fails
only because its input failed (existing join rule). Restart the target.

## (f) Residue — SC-005

After the runs: `^IRIS.Temp.sentaiTargetCred` has no entry for them; a search of the primary's
globals, `messages.log` and the evidence files for the target password, access or refresh token
finds nothing; the backend suite and frontend suites still pass (SC-007).
