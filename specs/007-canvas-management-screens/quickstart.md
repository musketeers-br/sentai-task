# Quickstart — 007 Canvas Management Screens (acceptance on the container)

Run against the dev container `sentai-task-iris-1`. Evidence goes to
`specs/007-canvas-management-screens/evidence/`. Tokens never go into an evidence file.
Credentials come only from the environment (`IRIS_USER`/`IRIS_PASSWORD`), as in the existing
e2e `tests/support.ts`.

Behaviour is defined in [contracts/api-consumption.md](contracts/api-consumption.md), and view
models in [data-model.md](data-model.md).

## Prerequisites

- **Part A** (US-1…US-4) needs spec 006 deployed (BD-3). **Part B** (US-5, US-6) needs spec 005
  deployed (BD-4) and the Part B prototype.
- Build and publish the canvas as today, then run the suites:

  ```bash
  cd frontend
  npm run generate:tokens && npm test          # unit
  npx playwright test                          # e2e, container up
  ```

  The existing suites must stay green: unit 48/48, e2e 13/13.
- Test setup may create platform tasks **only** through `POST /flows/{id}/schedule` (product API).
  It deletes them with the existing `deleteNativeTask` helper afterwards. Never suspend an instance
  task.

## US-1 — Catalog list and detail (SC-001)

1. Sign in, then choose *Task catalog* in the top bar. The URL gains `?view=catalog`.
2. **SC-001 comparison** (e2e `us7-catalog.spec.ts`):
   - read `GET /csp/sentai/api/v1/catalog/tasks` in the test with the same operator;
   - for every item, the row shows the same name, namespace, class, next run, last run, status,
     user, suspended mark and destructive or unknown mark;
   - open three details (task 4 *Integrity Check*, one SentaiTask task, one task with a
     `lastError`), and each detail field equals the item read;
   - no displayed value is missing from the API response;
   - write `evidence/us1-values.json` with `{taskId, field, shown, api, equal}` rows.
3. **Rows** are in `orderByNextRun` order, and the footer says "sorted by next run".
4. **Back and deep link**:
   - a deep link to `?view=catalog&task=4` opens the detail;
   - back returns to the canvas with the previously opened flow, and an unsaved edit is still
     there;
   - a reload keeps the catalog screen.

## US-2 — SentaiTask origin and the jump to the flow (SC-002)

1. Seed a 3-step flow with `seedFlow`, then schedule it through the API. Record the `taskIds`.
2. In the catalog, search `SentaiTask: <flowId>#`. Exactly 3 rows show "flow <id> · step 01/02/03".
3. **SC-002**: from the catalog, click a row (1) and then its flow link (2). The canvas opens with
   that flow. Record the click count in `evidence/us2-origin.json`.
4. Delete the flow as test setup. The mark reads "flow not found" and has no link.
5. Cleanup: delete the 3 tasks.

## US-3 — Filters and count

For each case, the rows equal the `items` of the API call with the same query, and the header
equals "`matched` of `total` tasks":
- text `integrity`;
- namespace `%SYS`;
- *Suspended*;
- *Scheduled*;
- *Destructive only*;
- one combination.

The namespace options equal the distinct namespaces of the unfiltered read.

## US-4 — Suspend and resume (SC-004)

1. Use a task from a seeded, scheduled flow; never an instance task.
2. Suspend it:
   - the button is disabled while pending;
   - afterwards the detail and the row show SUSPENDED;
   - a fresh `GET /catalog/tasks/{id}` agrees.
3. Resume it: the detail and the row show it active, and a fresh read agrees.
4. **Refusal**: sign in as a temporary operator without `%Admin_Task` (IRIS-generated password,
   never printed, user deleted afterwards).
   - The catalog shows "HTTP 403 — no reason given" and no rows.
   - A direct detail link shows the same.
5. Evidence: `evidence/us4-suspend.json`.

## US-5 — Declared custom steps (SC-005)

1. The palette's *Custom* group lists exactly the catalog entries with `executor: in-process`, plus
   legacy `custom`, which is disabled.
2. Drop `storage-headroom-check`. The inspector shows exactly one field, `minFreePercent`:
   - a number input with bounds 0–100;
   - placeholder `default: 10`;
   - the description as help text.

   Drop `db-size-report`, and the inspector shows "takes no parameters".
3. Set `minFreePercent` to 150, save and validate.
   - The `PARAM_OUT_OF_RANGE` message is shown verbatim, at field level if the finding carries
     `parameter` (BD-1), otherwise at step level.
   - The status bar counts it.
   - Record which level was used in `evidence/us5-params.json`.

## US-6 — Destructive declared type and legacy `custom` (SC-006)

1. Drop `purge-task-history`. The node shows the hazard band and the DESTRUCTIVE seal. Dispatch
   asks for the typed confirmation.
   - A wrong value → 428, with the detail shown verbatim.
   - The right value dispatches.
2. Open a saved flow with a legacy `custom` step. It shows "not supported", with the class
   read-only and no input.

## SC-003 — Timing with about 150 tasks

- Setup: schedule enough seeded integrity-check flows to reach about 150 tasks. Record the count.
- Time from choosing *Task catalog* to the first row visible: under **3 s**.
- Time from a filter change to the updated rows: under **2 s**.
- Record 3 runs of each in `evidence/sc003-timing.txt`.
- Delete every seeded task and flow afterwards, and check the count returns to the value before
  the run.

## SC-008 — Theming parity

Take paired screenshots at 1440×900, dark and light:
- the catalog screen with a destructive row selected;
- the inspector parameter form with one error (Part B).

They must pass the spec 002 US-6 structural, string and contrast assertions (same helpers as
`us6-theming.spec.ts`). Files go in `evidence/sc008-*.png`.

## Final check

- unit **48 → ~81** and e2e **13 → 23**, all green;
- no temporary user, task or flow remains;
- `git grep` finds no credential in `frontend/`.
