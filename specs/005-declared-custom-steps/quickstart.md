# Quickstart — 005 Declared Custom Steps (real-instance acceptance)

Target: `sentai-task-iris-1` (IRIS 2026.2), canvas/API at `http://localhost:52773/csp/sentai/`.
Operator: a user with administrative privileges (e.g. `_SYSTEM` on the dev image). Record status
and body of every call in `evidence/quickstart-http-<date>.json` — **never tokens or passwords**.
Contracts: [api-delta.md](contracts/api-delta.md); model: [data-model.md](data-model.md).

## Automated suite

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP
```

```objectscript
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
```

Expected: 0 failures, ~152 methods (plan.md). Frontend: unit 48/48; e2e 13/13 with three specs
adjusted for `switch-journal` becoming available (plan.md task 9).

## (a) SC-001 — three kinds of step, fan-out / fan-in

Flow: `01 storage-headroom-check` → { `02 db-size-report`, `03 integrity-check` }, all on
category `Default`.

1. `GET /catalog/step-types` → the 4 in-process types listed with `parameters`.
2. `POST /flows` → 201; `POST /flows/{id}/validate` → `errors: []`.
3. `POST /flows/{id}/dispatch` (with `runCredential`) → 202.
4. Poll `GET /runs/{guid}` → 01 `completed`, then 02 and 03 running together, all `completed`;
   step 02 `result.databases` lists the instance's databases with sizes; steps 01 and 02 show
   `executedAs` = the dispatching user (SC-006).

## (b) SC-005 — headroom forced to fail

Same flow with `01.parameters.minFreePercent = 99.9` (above the container's free space).
→ 01 `failed`, failure reason names each location and its free percentage vs. 99.9; 02 and 03
`failed` by the join; run `failed`. With the default (10) it completes (a).

## (c) SC-003 — parameter violations are caught before running

For each case, validate → error; dispatch → 422; schedule → 422; **0 runs created**:

| Case | Expected code |
|---|---|
| `purge-task-history` with `keepDays: "thirty"` | `PARAM_TYPE_MISMATCH` |
| `storage-headroom-check` with `minFreePercent: 150` | `PARAM_OUT_OF_RANGE` |
| `storage-headroom-check` with `path: "/etc"` | `PARAM_UNKNOWN` |

(`PARAM_REQUIRED` is covered by the unit suite: shipped types declare no required parameter.)

Also: `POST /flows/{id}/schedule` on the flow of (a) → 422 `IN_PROCESS_NOT_SCHEDULABLE` for 01 and
02, no native task created (ID-3).

## (d) SC-002 — legacy `custom` never runs

Flow with one `custom` step, `customClass: "%SYS.Task.SwitchJournal"`:
validate / dispatch / schedule → `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`; rerun of a pre-existing
failed custom step → 409 same code; `GET /flows/{id}` returns it unchanged. Journal file name
before == after.

## (e) SC-008 — classic wave and identity on the real path

Flow E1: `01 integrity-check` → `02 purge-task-history (keepDays 30)` → `03 switch-journal`.

1. `POST /flows/{id}/schedule` → 422 with `DESTRUCTIVE_NOT_SCHEDULABLE` (02) and
   `IN_PROCESS_NOT_SCHEDULABLE` (02, 03).
2. Dispatch without confirmation → 428 naming 02; with the typed confirmation → 202.
3. Run → all `completed`; current journal file changed (record before/after names); 02 and 03
   `executedAs` = the administrative dispatcher.
4. **MANDATORY — unprivileged operator over REST (D-1 on the real path).**
   - Create a temporary IRIS user with a role that can use the product and read WQM categories but
     holds no administrative database privilege (start from the R-1 role `%DB_IRISAPP_CODE:R,
     %DB_IRISAPP_DATA:RW` and add only what sign-in and the category read require — record the
     final role in the evidence). Password generated inside IRIS, never printed or stored; user and
     role deleted afterwards.
   - Flow E2: `02 purge-task-history` and `03 switch-journal` as **independent roots** (no
     integrity check, so no join failure hides the platform's answer).
   - As that user: sign in, `POST /flows`, validate (`errors: []`), dispatch with the typed
     confirmation for 02 and its own `runCredential` → 202.
   - Expected: 02 and 03 `failed`, each `failureReason` containing the platform's `<PROTECT>` text
     **verbatim**; `executedAs` = the temporary user; journal file name unchanged.
   - Evidence: the run read (status + body, no tokens) and the before/after journal file name.
5. **Run credential of another user** → `/dispatch` as user A with a `runCredential` redeemed from
   user B → 403 `RUN_CREDENTIAL_USER_MISMATCH`, no run created (ID-1).
6. **Re-run by someone else** → a failed step of a run dispatched by A, `/rerun` as B → 403
   `RERUN_NOT_BY_DISPATCHER`; as A → 202 while the run is live (ID-2).

## Evidence / notes

- Phase 0 spikes and outputs: [research.md](research.md).
- Default timeout 60 min when `timeoutMinutes` is 0, counted from `running` (includes waiting for a
  worker); work may continue after a timeout or cancel (F-2).
