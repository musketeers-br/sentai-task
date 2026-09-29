# Quickstart: validating in-process embeddings (spec 017)

Runs against the compose stack. Shared setup:

```bash
TOKEN=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login | jq -r .access_token)
API=http://localhost:52773/csp/sentai/api/v1
AUTH="Authorization: Bearer $TOKEN"
search() { curl -s -H "$AUTH" --get --data-urlencode "q=$1" "$API/catalog/step-types/search"; echo; }
```

## 1. Fresh clone → up → search (US1, US2, SC-001, SC-002, SC-004)

```bash
docker compose down --rmi local && docker image rm ollama/ollama:latest 2>/dev/null
docker compose up -d --build
docker compose ps --format '{{.Service}}'          # iris, iris-target — no ollama
docker images --format '{{.Repository}} {{.Size}}' | grep -E 'sentai|ollama'
```

✅ Only `iris` and `iris-target` run; no `ollama` image is pulled.
✅ Record image sizes and build time in `evidence/` (SC-001: ≥ 5 GB less than before).

As soon as `iris` reports healthy, wait for the worker (research R-2, ~7–11 s) and search:

```bash
docker exec sentai-task-iris-1 iris session iris -U IRISAPP \
  'write ^IRIS.Temp.sentai.embed("state"),!'       # ready
search 'free up disk space'
```

✅ `{"available":true,"matches":[{"type":"storage-headroom-check",…}` within one second.
✅ Repeat for *check my globals are sound* → `integrity-check`, *get rid of old audit records* →
`purge-audit-records`, *rotate the journal* → `switch-journal` (research R-5 table).
✅ `search 'order me a pizza'` → `{"available":true,"matches":[]}`.

## 2. The `warming` answer (US2 scenario 2, FR-004a)

```bash
docker restart sentai-task-iris-1 && until docker exec sentai-task-iris-1 iris qlist >/dev/null 2>&1; do sleep 1; done
search 'free up disk space'      # immediately, before the worker is ready
```

✅ `{"available":false,"reason":"warming"}` with HTTP 200 — or a ranked answer, if the worker was
already ready. A few seconds later the same search ranks.

## 3. No network at run time (FR-003)

```bash
docker network disconnect sentai-task_default sentai-task-iris-1
docker exec sentai-task-iris-1 iris session iris -U IRISAPP \
  'do ##class(sentai.search.EmbeddingWorker).Stop() hang 1 do ##class(sentai.search.EmbeddingWorker).Start()'
# wait for state=ready, then search from inside the container, e.g. through an iris session
docker network connect --alias iris sentai-task_default sentai-task-iris-1   # restore the alias
```

✅ The worker is ready in seconds (research R-3: 6.6 s offline, not 146 s).

## 4. Switching provider rebuilds the corpus (US3, SC-005)

Covered by the backend suite (`StepSearchServiceTest`, fake provider, two models of equal length).
Manually: point `sentai-steps` at another configuration of length 384, search, and check that every
`sentai_search.StepCorpus.providerIdentity` names the new configuration.

## 5. Existing stack (US5, R-6)

A stack built before this feature and brought up with `docker compose up -d` (no `--build`):

```bash
search 'free up disk space'      # {"available":false,"reason":"unreachable"} — ollama is gone
docker compose up -d --build
search 'free up disk space'      # ranks
```

## 6. IPM install unchanged (FR-003a, R-7)

On an instance without the Python packages: `zpm "install sentai-task"`, then
`search 'free up disk space'` → `{"available":false,"reason":"not-configured"}`. No package, model
or row was installed.

## 7. Demo (US4)

`scripts/demo/up.sh` on a host with the `.env` it requires, then sign in as the demo user and search
*rotate the journal* in the palette. ✅ SUGGESTED shows `switch-journal`; `docker compose ps` lists no
`ollama`.

## 8. Suite

`zpm "test sentai-task -only"` → all passed (375 + the new tests); `npm test` and `npm run check` in
`frontend/` green.
