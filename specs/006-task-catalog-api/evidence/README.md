# Evidence — 006 Task Catalog API (quickstart on the real instance)

- **Instance**: container `sentai-task-iris-1`, IRIS for UNIX 2026.2 (Build 221U), namespace
  `IRISAPP`.
- **Captured**: 2026-09-26.
- **Operator**: the dev container's documented default account, passed only through
  `IRIS_USER`/`IRIS_PASSWORD`.
- **No secrets**: no token, password or `Authorization` header appears in any file here (checked
  with `grep` for `eyJ`, `Bearer`, `access_token` and `refresh_token`).

## Results

| Criterion | Result | File |
|---|---|---|
| **SC-001 / SC-002** field-by-field, every task | ✅ **pass**, run twice (see below) | `a-field-compare.json` (second run) |
| **SC-003** SentaiTask origin | ✅ **pass** | `b-origin.json` |
| **SC-004** suspend then resume | ✅ **pass** | `c-suspend-resume.json` |
| Operator without task privilege | ✅ **refused verbatim** after the gate fix (`d-refusal.json` is the before) | `g-gate-fix.json` |
| `/schedule` through the platform | ✅ **pass** | `h-schedule-via-platform.json` |
| **SC-005** full list < 2 s | ✅ **pass** | `e-timing.txt` |
| **US-5** recent runs | ✅ **pass** | `f-recent-runs.json` |

### SC-001 / SC-002 — `a-field-compare.json`

Product 153 = platform 153 tasks; 1683 rows (153 × 11 fields); 0 mismatches; 0 undocumented keys;
the item read equals the list item for every task.

The script ran twice:
1. **19 tasks** (the instance as it is): 209 rows, all equal.
2. **153 tasks**, including about 131 temporary tasks and a task whose last run **failed**. This
   run exercised the decoded `status` against the platform's own `GetErrorText`.

The first attempt of run 2 reported one mismatch. It was a bug in the comparison script, not in
the product: the script read the platform's serialized `%Status` file in the container without
UTF-8 translation. The script was fixed (`TranslateTable="UTF8"`), and the product's value
(`ERROR #5001: Q006 deliberate failure`) then matched.

### SC-003 — `b-origin.json`

- A 3-step flow scheduled through the product gave exactly 3 tasks with `origin` for steps
  01/02/03.
- The near-miss `SentaiTask: <id>#01 copy` was not marked.
- After the flow was deleted: `flowExists: false` and `destructiveUnknown: true` for all three.

### SC-004 — `c-suspend-resume.json`

- **Suspend**: the product answered 200 with `suspended: true`, and the platform's info read
  agrees (`Suspended: true`). `nextRun` was kept, as the platform keeps it.
- **Resume**: 200 with `suspended: false`, and the platform agrees.
- **Unknown task**: 404 with the platform's `ERROR #5809…` verbatim.

### SC-005 — `e-timing.txt`

| Tasks on the instance | Five runs |
|---|---|
| 20 | 0.060–0.065 s |
| 151 | 0.401–0.407 s |

### US-5 — `f-recent-runs.json`

- **Succeeding task**: `recentRuns[0]` has `Status "1"` / `Result "Success"`, and `lastError` is
  `"Success"`.
- **Failing task**: `status` = `recentRuns[0].Status` = `ERROR #5001: Q006 deliberate failure`.
- `TASKMGR` administrative rows were excluded.
- List items carry no `recentRuns`.

## Finding — the platform's refusal did not reach the operator verbatim (fixed)

**Before** (`d-refusal.json`): the product's token gate (`Dispatcher.IsTokenValid`, spec 003
R-002 fallback) called `GET /api/admin/info` and treated anything but 200 as an invalid token. The
platform answers 403 there to an operator without task privilege, so every catalog call answered
`401 Invalid or expired token`. Nothing was granted, but the platform's reason never reached the
operator.

**Fix.** A 403 on `/api/admin/info` proves the token authenticated; the gate lets the request
through and each endpoint returns the platform's own answer. It grants nothing: the REST web app
authenticates with the platform's JWT and runs with the operator's own roles (no MatchRoles).
Unit tests: `AuthenticationTest` (+2).

**After** (`g-gate-fix.json`): an invalid token is still 401 (platform and product); the
operator's list, item and suspend are the platform's 403 with `platformStatus`; the temporary
task stayed unsuspended.

**What the fix exposed, and its fix.** With the gate open to such an operator, `/schedule` was
reachable, and it created `%SYS.Task` **in-process** — the path that skips `%Admin_Task` (research
R-1). The platform has `POST /api/admin/v2/task` (`%Api.Admin.Endpoints.Task.CRUD`, which accepts
`%Admin_Task` or `%Admin_Operate`; its body requires every schema field; the answer carries no id).
`/schedule` now creates each task there with the operator's token (`sentai.dispatch.NativeScheduler`):
the id comes from the platform's list (newest task of that name); a refusal is returned verbatim
and earlier creates of the same request are deleted; a failed read of the flow's steps is its own
refusal (`SQLCODE -99` → 403), never "0 steps, scheduled". Unit tests: `ScheduleViaPlatformTest`
(+7), `ScheduleEndpointTest` adjusted (1).

`h-schedule-via-platform.json`: the administrator gets one task per step, `RunAsUser` = the caller,
`IsRoot` from the edges, and the catalog resolves the origin; the operator without SQL privilege
gets `403 SQLCODE -99` verbatim; with SELECT on the product schema the operator is stopped at
validation (see the next finding); in both cases no task is created and the flow's
`scheduleSpec` is not recorded.

**Open (not changed).** Schedule validation reports a platform refusal of the WQM category read as
`CATEGORY_NOT_FOUND` ("does not exist"). Same class of mislabel as the old 401; it belongs to the
spec 004 validator.

## Test counts

| Suite | Before 006 | After 006 | Adjusted | Removed |
|---|---|---|---|---|
| Backend | 122/122 | **169/169** (+47); **178/178** after the gate and schedule fix (+9) | 3 (2 in `CatalogTasksTest`, 1 in `ScheduleEndpointTest`) | 0 |
| Frontend unit | 48/48 | 48/48 | — | — |
| Frontend e2e | 13/13 | 13/13 | — | — |

## Cleanup (verified)

- The `%SYS.Task` count is 19 before and 19 after.
- 134 temporary tasks and 270 history rows were deleted. The scheduled SentaiTask tasks and the
  near-miss task were deleted through the management API.
- The temporary user and role were deleted (`user:0 role:0`), and so were the temporary classes
  (`left:00`).
- `/tmp` files were removed. The `IRIS_USER`/`IRIS_PASSWORD` values were never written to a file.
