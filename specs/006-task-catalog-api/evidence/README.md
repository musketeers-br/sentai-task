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
| Operator without task privilege | ⚠️ **refused, but not verbatim** (see the finding below) | `d-refusal.json` |
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

## Finding — the platform's refusal does not reach the operator verbatim

**What happens.** An operator whose roles are only `%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW`
(no `%Admin_Task`) signs in successfully. The platform then answers **403** to that operator's
`GET /api/admin/info`. The product's token gate (`Dispatcher.OnPreDispatch` → `IsTokenValid`,
spec 003 research R-002 fallback) validates **every** request with that same `/api/admin/info`
call and treats anything but 200 as an invalid token. So every catalog call, including list,
item and suspend, answers:

```json
401 {"status":401,"title":"Unauthorized","detail":"Invalid or expired token"}
```

**Effect.**
- The operator is refused, and the task stayed unchanged, so nothing was granted. Constitution III
  is not breached on authority.
- The refusal is **not** the platform's verbatim 403, and it is mislabelled as an expired token.
  The catalog's own verbatim-refusal path (proven by the unit tests `TaskReadTest`,
  `TaskSuspendTest`) is never reached on this instance for such an operator.
- The canvas reacts to a 401 by asking the operator to sign in again.

**Why it is not fixed here.** The gate belongs to the product's authentication layer (spec 003)
and applies to every endpoint. Changing it is outside this feature's tasks and needs its own
decision.

**Fix to decide.** A platform 403 on `/api/admin/info` proves the token authenticated. The gate
could let the request through, and each endpoint would then return the platform's own refusal
(403 with `platformStatus`) verbatim. The alternative is to keep the gate and document the 401.

## Test counts

| Suite | Before 006 | After 006 | Adjusted | Removed |
|---|---|---|---|---|
| Backend | 122/122 | **169/169** (+47) | 2 (both in `CatalogTasksTest`) | 0 |
| Frontend unit | 48/48 | 48/48 | — | — |
| Frontend e2e | 13/13 | 13/13 | — | — |

## Cleanup (verified)

- The `%SYS.Task` count is 19 before and 19 after.
- 134 temporary tasks and 270 history rows were deleted. The scheduled SentaiTask tasks and the
  near-miss task were deleted through the management API.
- The temporary user and role were deleted (`user:0 role:0`), and so were the temporary classes
  (`left:00`).
- `/tmp` files were removed. The `IRIS_USER`/`IRIS_PASSWORD` values were never written to a file.
