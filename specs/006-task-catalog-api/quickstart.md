# Quickstart — 006 Task Catalog API (acceptance on the real instance)

These steps run against the dev container `sentai-task-iris-1` (IRIS 2026.2), and all outputs go to
`specs/006-task-catalog-api/evidence/`. Tokens and passwords never go into an evidence file:
headers are written as `<REDACTED>`, as in spec 001.

Field semantics are in [data-model.md](data-model.md), and shapes and error codes are in
[contracts/api-delta.md](contracts/api-delta.md).

## Prerequisites

- The container is up, and the module is loaded (`zpm "load /home/irisowner/dev/ -v"`). The
  backend suite is green (`zpm "test sentai-task -only"`).
- **Privileged operator**: an IRIS user with `%Admin_Task` who can call `/csp/sentai/api/v1`.
  Credentials are passed only through `IRIS_USER` / `IRIS_PASSWORD` in the environment, as in the
  spec 001 script.
- **Unprivileged operator** for (d): a temporary user who can sign in to the product but has no
  task privilege (the recipe in research R-1: `%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW`). The
  password is generated inside IRIS and never printed. The user is deleted at the end.
- Product token: `POST /api/admin/login` (Basic), then `Authorization: Bearer` on
  `/csp/sentai/api/v1/...`.

## (a) SC-001 / SC-002 — field-by-field comparison, every task

Script: `scripts/catalog-evidence/compare.sh`, delivered in task 5 (bash + curl + jq, same helpers
as `scripts/validate-async-job-contract/lib/`). For each task:

1. `GET /csp/sentai/api/v1/catalog/tasks`, keeping `total` and `items`.
2. `GET /api/admin/v2/tasks`, then for every `Id`, `GET /api/admin/v2/task?id=` and
   `GET /api/admin/v2/task/info?id=`, all with the same operator.
3. Compare each field against the mapping in data-model.md:
   `class=TaskClass`, `runAsUser=RunAsUser`, `timePeriod=TimePeriod`, `nextRun=NextScheduled`,
   `lastStarted`, `lastFinished`, `lastError=Error`, `suspended=Suspended`, and
   `status = "1"` or the platform text of `Status`. The script decodes `Status` with the same
   platform function through a one-line `iris session` call, and never implements the decoding
   itself.
4. Check SC-002: no key outside the documented set appears on any item. Every documented key is
   either present with the platform's value or listed in `unavailable[].fields`.
5. Also compare `GET /catalog/tasks/{id}` for every id against its list item (US-1 scenario 4).

**Pass**: `evidence/a-field-compare.json` has one row per task and per field with
`{taskId, field, product, platform, equal}`. The run passes when `equal` is true for **100%** of
rows, `total` equals the platform list count, and there are 0 undocumented keys. The script exits
non-zero on any mismatch.

## (b) SC-003 — SentaiTask origin

1. Create a 3-step `integrity-check` flow through the product API, then
   `POST /flows/{id}/schedule`. Record the returned `taskIds`.
2. `GET /catalog/tasks?q=SentaiTask: <id>#` → **exactly 3** items. Each must carry
   `origin = {flowId:"<id>", stepId:"01|02|03", flowExists:true}` and `destructive:false,
   destructiveUnknown:false`. No other task may carry that `flowId`.
3. Near-miss: create one task by hand in the portal (or in-process as the container user, which is
   test setup only) named `SentaiTask: <id>#01 copy`. It must have no `origin`.
4. Delete the flow (`DELETE` is not in the API, so remove it through the persistence layer as test
   setup) → the same 3 tasks keep `origin` with `flowExists:false`, and they become
   `destructiveUnknown:true`.
5. Cleanup: delete the 3 tasks and the near-miss task, record the `%SYS.Task` count before and
   after, and check that it is unchanged.

**Pass**: `evidence/b-origin.json` shows the four reads above.

## (c) SC-004 — suspend and resume

Use one of the tasks from (b), or a temp task. **Never use an instance task.**

1. `POST /catalog/tasks/{id}/suspend {"suspended":true}` → 200, and the body shows
   `suspended:true`.
2. Platform read `GET /api/admin/v2/task/info?id=` → `"Suspended":true`. Record `NextScheduled`,
   which the platform keeps (R-3).
3. `POST … {"suspended":false}` → 200, `suspended:false`. The platform info read then shows
   `"Suspended":false`.
4. `POST /catalog/tasks/99999/suspend` → 404 with `detail` `ERROR #5809: …` verbatim.

**Pass**: `evidence/c-suspend-resume.json` has the product responses and the platform reads after
each call.

## (d) Operator without privilege → verbatim refusal

As the unprivileged operator:

- `GET /catalog/tasks` → 403 with `platformStatus = {"errors":[],"summary":""}`;
- `GET /catalog/tasks/4` → 403;
- `POST /catalog/tasks/<temp id>/suspend` → 403. A privileged info read afterwards shows the task
  unchanged.

Then delete the user and its role.

**Pass**: `evidence/d-refusal.json`.

## (e) SC-005 — timing

Time `GET /catalog/tasks` five times with `curl -w '%{time_total}'` at the instance's current
count (≈ 22 tasks). Then time it again after adding temp tasks to about 150 (test setup
in-process, deleted afterwards).

**Pass**: every run is under **2 s**. Evidence: `evidence/e-timing.txt`. Research R-2 measured
the platform reads alone at 0.38 s for 151 tasks.

## (f) US-5 — recent runs (R-4 proven → included)

1. Temp task A (succeeds) and temp task B (fails). Start them with
   `POST /api/admin/v2/task/run?id= {"RunNow":true}`, which is test setup and not a product
   feature, then wait until `LastFinished` is set.
2. `GET /catalog/tasks/{A}` → `recentRuns[0]` has `Status:"1"`, `Result:"Success"`, and its
   `LastStart`/`Completed` equal the platform history row. `lastError` is `"Success"`.
3. `GET /catalog/tasks/{B}` → `recentRuns[0].Status` = `ERROR #…` verbatim, and `status` (the
   catalog task field) equals the same text.
4. The list items for A and B carry **no** `recentRuns`, and neither does a task with only
   create/suspend events (it gets `recentRuns: []` on the item read).
5. Clean up the tasks and their history rows (as in research).

**Pass**: `evidence/f-recent-runs.json`.

## Cleanup check (always)

- `%SYS.Task` count is equal to the count before the run.
- No temp users or roles remain.
- No `SpikeR006*` or temp history rows remain.
