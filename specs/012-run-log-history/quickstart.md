# Quickstart: Run Log and Run History

On the dev stack (`http://localhost:52773/csp/sentai/`, `_SYSTEM` / `SYS`), after
`LoadDir` of `src` and `bash scripts/publish-canvas.sh`.

## 1. The log of a run (US1)

1. *Open flow…* → *Example: storage health check* → *Run now*.
2. While and after it runs, the **RUN LOG** panel shows, oldest first:
   `Run dispatched by _SYSTEM (flow revision n, 2 steps)` → two `started on local` → two
   `completed in …` → `Run completed: 2 completed, 0 failed, 0 cancelled (…)`.
3. Run a flow `01 storage-headroom-check` (`minFreePercent: 100`, which always fails) → `02
   db-size-report` behind a join: the log shows `#01 failed after …: "<the step's reason>"` with
   `ERROR`, then `#02 not started: input #01 failed (all inputs must succeed)`.
4. With `iris-target` up, run a flow with a remote integrity check, then
   `docker compose stop iris-target` for about a minute and start it again: the log shows one
   `Target iris-target did not answer …` and one `Target iris-target answers again`.

API check:

```bash
TOKEN=$(curl -s -u _SYSTEM:SYS -X POST localhost:52773/api/admin/login -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)
curl -s -H "Authorization: Bearer $TOKEN" localhost:52773/csp/sentai/api/v1/runs/<guid> | jq '.log[] | [.at,.severity,.message]'
```

## 2. History (US2)

```bash
curl -s -H "Authorization: Bearer $TOKEN" 'localhost:52773/csp/sentai/api/v1/runs?limit=2' | jq '.[] | {seq,flowName,state,stepCounts}'
curl -s -H "Authorization: Bearer $TOKEN" 'localhost:52773/csp/sentai/api/v1/runs?limit=2&before=<last seq>' | jq length
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" 'localhost:52773/csp/sentai/api/v1/runs?limit=500'   # 400
```

In the canvas: *Runs* tab → newest first; filter *Flow* = the example, *Outcome* = completed; open
one → read-only run view with its log; *Back to runs* keeps the filters. On *Flows*, *More → Run
history* opens *Runs* filtered to the open flow.

## 3. Export (US3)

In any run view, choose *Export*. `Example-storage-health-check-<8 chars>.json` is saved.
`jq '.steps | length, .log | length'` matches the view.
