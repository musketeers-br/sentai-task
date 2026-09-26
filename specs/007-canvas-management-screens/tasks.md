# Tasks: Canvas Management Screens (frontend)

**Input**: Design documents from `/specs/007-canvas-management-screens/`. [plan.md](plan.md) is
the source of truth where it conflicts with [spec.md](spec.md). The other design documents are
[research.md](research.md) (R-1…R-7 and the FR-019 audit), [data-model.md](data-model.md),
[contracts/api-consumption.md](contracts/api-consumption.md) and [quickstart.md](quickstart.md).

**Tests**: REQUIRED (Constitution: TDD). Every code task writes its failing test **first**:

- unit tests (vitest) for pure modules, using fixtures copied from the 005/006 `api-delta.md`
  files;
- e2e tests (Playwright) per user story, against the container.

No test is removed.

**Run unit + e2e.** Every code task ends with this, from the repo root:

```bash
cd frontend && npm run generate:tokens && npm test && npx playwright test
```

Container up; canvas published as today. While a task's **gate** is not met, run the unit suite
and only the existing e2e tests (`npx playwright test --grep-invert "us(7|8|9|10|11|12|13|14)-"`).
Run the task's new spec as soon as its gate opens.

**Test counts**:

- **Unit 48 → ~81.**

  | Area | Tests |
  |---|---|
  | Catalog wire/view | 7 |
  | Sort | 4 |
  | Refusal/status | 4 |
  | Filters/namespaces | 3 |
  | Origin/recentRuns | 3 |
  | Action reducer | 2 |
  | Step-type wire and grouping | 3 |
  | Params | 5 |
  | Confirmations | 2 |

- **e2e 13 → 24.**

  | Spec | Tests |
  |---|---|
  | `us7` | 2 |
  | `us8` | 1 |
  | `us9` | 1 |
  | `us10` | 2 |
  | `us11` | 2 |
  | `us12` | 1 |
  | `us13` | 1 |
  | `us14` | 1 |

- **Removed: 0.** If 005's implementation adjusts the `us1` palette assertion (switch-journal no
  longer "not supported"), that adjustment belongs to **005 T014**, not to this spec.

**Hard rules for every task** (Constitution I–IV, plan):

- **No business logic in the browser (FR-019).** Destructiveness, origin, availability, filtering,
  counting and validation come from the API. The frontend displays and orders only.
- **No free-text field that names a class or a parameter key** (FR-013, FR-018).
- **Refusals are shown verbatim.** Show `HTTP <status> — <detail | platform errors | "no reason
  given">`, and keep `platformStatus`/`platformInfo` untouched.
- **Components never call `fetch` or read wire keys.** Only `src/lib/api/client.ts` and
  `src/lib/api/wire.ts` / `src/lib/catalog/catalog.ts` adapters do.
- **Credentials.** None are committed. e2e reads `IRIS_USER`/`IRIS_PASSWORD` from the environment
  (existing `tests/support.ts`). Temporary operators get a password generated at run time
  (`crypto.randomBytes`) that is never logged. Every temporary user, role, flow and platform task
  created by a test is removed in `afterAll`/`finally`.
- **Out of scope.** No backend change; no DevExtreme; no New task/edit/delete/run-now; no
  History/WQM screens; no `result`/`executedAs` on the live run; no background polling. No
  confidential names; the repository is public.
- **Sequential files.** `frontend/src/routes/+page.svelte`, `frontend/src/lib/shell/TopBar.svelte`,
  `frontend/src/lib/api/client.ts` and `frontend/src/lib/inspector/Inspector.svelte` are edited by
  one task at a time.

## Format: `[ID] [P?] [Story] Description`

- **[P]** means parallelizable: no file in common with an incomplete task.
- **[Story]**:
  - US1: see the platform's tasks
  - US2: recognise SentaiTask tasks
  - US3: filters
  - US4: suspend/resume
  - US5: declared custom steps
  - US6: destructive declared types and legacy `custom`
- **Plan row → task**:
  - T0 → T001
  - rows 1–7 → T002–T009 (rows 1–5 → T002–T006; rows 6 and 7 → T007, T008)
  - row 8 is **split**: typed confirmation → T009; declared node and legacy custom → T010
  - row 9 → T011

  The IDs are consecutive in row order: T002 (1), T003 (2), T004 (3), T005 (4), T006 (5),
  T007 (6), T008 (7), T009 (8a), T010 (8b), T011 (9).

**Gates** (repeated in each task header):

| Gate | Condition | Tasks |
|---|---|---|
| **G-A** | Spec 006 T001–T005 implemented on the container (BD-3) | Part A e2e: T002–T006 |
| **G-B** | T001 prototype exists in `design/` **and** spec 005 T001–T008 + T013 implemented on the container (BD-4) | Part B visual tasks: T007, T008, T010 |
| **G-C** | Spec 005 T013 implemented on the container, and `purge-task-history` set `available: true` **temporarily and uncommitted on the dev container only** (reverted after the run, recorded in the evidence) — the committed flip (005 T016) comes **after** T009 is merged, never before | The e2e of T009 (and T010's destructive-node e2e); T009's code and unit tests are ungated |

Unit tests never wait for a gate.

---

## Phase 1: Setup (docs and design)

- [X] T000 Reconcile `specs/007-canvas-management-screens/spec.md`, `plan.md` and
  `specs/005-declared-custom-steps/tasks.md`. This is docs only, with no code.

  **1. `specs/007-canvas-management-screens/spec.md`:**
  - (a) Replace "in-platform" with the contract value **"in-process"** in Clarifications Q1,
    FR-012 and Assumptions.
  - (b) Add `### Session 2026-09-26 (plan)` under Clarifications, with bullets pointing to
    [plan.md §Spec deviations](plan.md) and [research.md](research.md) R-1, R-4, R-7 and the
    FR-019 audit.
  - (c) Apply the plan's four deviations:
    1. **US-5.4 / FR-015 / SC-005.** Errors are shown on the field matched by the finding's
       structured `parameter` (spec 005 BD-1). Findings without `parameter` (e.g. `PARAM_UNKNOWN`)
       are shown at step level, verbatim. Message text is never parsed.
    2. **Rewrite US-5.5.** "An unchanged parameter is not stored: the key is omitted and the
       declared default is shown as the field's placeholder; the backend applies the default."
       Align FR-016 with this.
    3. **Design brief item 5.** "the typed-confirmation input is **new** (the current dialog has
       none)". Add to FR-017 that dispatch collects one typed value per destructive step and shows
       a 428 `detail` verbatim.
    4. **FR-002.** "addressable through the page's query string (`?view=catalog&task=<id>`)".

  **2. `specs/007-canvas-management-screens/plan.md`:**
  - In `contracts/api-consumption.md` §Backend dependencies and in the plan's Spec deviations,
    change BD-1 and BD-2 from "backend dependencies" to "**included in 005 tasks** (T008 and T002
    respectively)".
  - Update the row-8 split and the e2e count **13 → 24**.

  **3. `specs/005-declared-custom-steps/tasks.md`.** BD-1 and BD-2 are **not there yet**. Add
  them as text inside the existing tasks, with no renumbering:
  - **T008**: "each `PARAM_REQUIRED` / `PARAM_TYPE_MISMATCH` / `PARAM_OUT_OF_RANGE` finding also
    carries `"parameter": "<name>"` (additive; `PARAM_UNKNOWN` carries the unknown key as
    `parameter`); one assertion per code (spec 007 BD-1)".
  - **T002**: "declare `purge-audit-records`' `parameters: [{"name":"daysToKeep","property":…,
    "type":"integer","required":true,"min":1,…}]` so the canvas can drop its local field (spec 007
    BD-2); `available` stays `false`".
  - **T016**: "`purge-task-history` is flipped to `available: true` only after spec 007 T009
    (typed confirmation in the dispatch dialog) is merged".

  Commit as docs only.

- [ ] T001 [P] Produce the **Part B prototype** (plan T0) in the design tool, in the visual system
  of `design/System.dc.html`, in **both themes**. Save it as `design/CustomSteps.dc.html` (dark)
  and `design/CustomStepsLight.dc.html` (light). This is design only, with no code, and it can run
  in parallel with T002–T006. It must show:
  1. The palette with a *Custom* group: 2 available declared types (one with parameters, one
     without), 1 unavailable declared type ("not supported"), and legacy `custom`
     ("not supported").
  2. A declared node, normal and destructive. The destructive one has the hazard band, the
     DESTRUCTIVE seal and the category left border.
  3. The inspector parameter form for 4 parameters (string, integer, number with bounds,
     boolean), with:
     - required marks;
     - one field showing `default: …` as placeholder;
     - description help text;
     - **one field in error**, plus the **step-level error list** variant;
     - the "takes no parameters" variant.
  4. Legacy `custom` in the inspector: not supported, with the class read-only.
  5. For reference, the **typed-confirmation** dialog as T009 implements it: one field per
     destructive step and the 428 error state. T009 does not wait for this item.
  6. The status bar counting a parameter error.

---

## Phase 2: Foundational

None beyond Phase 1. T002 (navigation) is the base of every catalog story, and the existing shell
serves Part B.

---

## Phase 3: User Story 1 — See the platform's scheduled tasks (P1) 🎯 MVP

**Goal**: *Task catalog* is reachable from the top bar and addressable. It lists every task with
only API values, and handles unavailable values and refusals.

**Independent test**: `us7-catalog.spec.ts`. Every row and value equals `GET
/csp/sentai/api/v1/catalog/tasks` (SC-001). Deep link, back and reload all work.

- [ ] T002 [US1] Navigation and routing (plan row 1). **Gate: e2e needs G-A.**

  **Test first**, in `frontend/tests/us7-catalog.spec.ts`, test 1 "navigation":
  1. sign in and open a seeded flow (`seedFlow`);
  2. edit the TaskName without saving;
  3. click *Task catalog* → the URL has `view=catalog`;
  4. back → the canvas shows the same flow with the unsaved edit;
  5. forward → the catalog;
  6. a deep link to `?view=catalog` after sign-in → the catalog;
  7. reload → still the catalog.

  Implement:
  - `frontend/src/lib/shell/TopBar.svelte`: nav buttons *Flows* and *Task catalog*, the active one
    marked with `aria-current="page"`. Flow actions (name input, Save, Validate, Schedule, Run)
    render only on Flows. Theme, user and Sign out render on both. No History or WQM entries.
  - `frontend/src/routes/+page.svelte`:
    - derive `view`/`task` from `page.url.searchParams` (`$app/state`);
    - navigate with `goto(url, { keepFocus: true, noScroll: true })`;
    - change `syncUrl()` to `goto(url, { replaceState: true, keepFocus: true, noScroll: true })`,
      keeping `flow`/`run`;
    - keep the one `FlowEditor` instance;
    - mount `frontend/src/lib/catalog/CatalogScreen.svelte` (new, a placeholder list of
      name/namespace from the API) when `view=catalog`.
  - If the e2e shows that `goto` remounts the page (plan Risks), switch to the documented fallback:
    a `view` store synced by `replaceState`, and `popstate` for back.

  Run unit + e2e.

- [ ] T003 [US1] List: columns, sort, unavailable values, refusal (plan row 2). **Gate: e2e needs
  G-A.**

  **Unit first**, in `frontend/src/lib/catalog/catalog.test.ts`. Fixtures are the 006 api-delta
  items: task 4, task 1000, and the task with an `unavailable` info read.

  | Area | Tests | What they cover |
  |---|---|---|
  | Wire → view | 7 | every field of `CatalogTaskView`; `Value` as value / unavailable (reason from `platformStatus`) / absent; `destructive` yes/no/unknown; deprecated `isDestructive`/`lastRun` **not read**; `className` read only from wire `class` |
  | `orderByNextRun` | 4 | timestamps ascending; then other text; then `""`; then absent; stable ties by name/taskId |
  | `refusalText` and `statusLabel` | 4 | `detail`; errors joined; `"no reason given"` for `{errors:[],summary:""}`; `statusLabel("1") === "OK (1)"`, other status verbatim |

  **e2e**, in `frontend/tests/us7-catalog.spec.ts`, test 2 "values":
  - **SC-001**: the rows equal the API items in `orderByNextRun` order. For each row, the name,
    namespace, class, next run, last run, status, user, SUSPENDED mark and DESTRUCTIVE or
    unknown mark equal the API values. The footer reads "sorted by next run" and
    "updated N s ago".
  - Write `specs/007-canvas-management-screens/evidence/us1-values.json`.
  - **Refusal**: create a temporary operator without `%Admin_Task` at run time (admin API or
    `docker exec … iris session`; generated password; deleted in `finally`). Signed in as that
    operator, the catalog shows "HTTP 403 — no reason given" and no rows.

  Implement:
  - `frontend/src/lib/api/client.ts`: `api.catalogTasks(filters)`. Extend `ApiError.problem` with
    `platformStatus?` and `platformInfo?`, passed through untouched.
  - `frontend/src/lib/catalog/catalog.ts`: `fromWireCatalogTask`, `fromWireCatalogPage`,
    `orderByNextRun`, `refusalText`, `statusLabel`.
  - `frontend/src/lib/catalog/CatalogValue.svelte`: value, unavailable with its reason, or "—" for
    absent.
  - `frontend/src/lib/catalog/CatalogScreen.svelte`: table with the columns of data-model; the
    refused state (FR-010); the footer; a refresh button (FR-011); no polling.

  Reuse tokens and `StateShape`-style glyphs. Do not recreate the prototype's invented state
  column. Run unit + e2e.

---

## Phase 4: User Story 3 — Filter and search the catalog (P2)

This phase follows plan row 3, which comes before row 4.

**Goal**: search, namespace, *All / Scheduled / Suspended* and *Destructive only* are sent to the
API, and the header shows "N of M tasks".

**Independent test**: `us9-catalog-filters.spec.ts`. For each filter, the rows and counts equal
the API's answer for the same query.

- [ ] T004 [US3] Filters and count (plan row 3; depends on T003). **Gate: e2e needs G-A.**

  **Unit first**, in `frontend/src/lib/catalog/catalog.test.ts`. Three tests:
  1. `namespaceOptions(page)`: the distinct namespaces of an unfiltered page, plus `all`.
  2. `catalogQuery(filters)`: omits defaults; `destructiveOnly=1`.
  3. The sequence guard: a stale response is ignored.

  **e2e**, in `frontend/tests/us9-catalog-filters.spec.ts`. One test covering:
  - text `integrity`;
  - namespace `%SYS`;
  - *Suspended*;
  - *Scheduled*;
  - *Destructive only*;
  - one combination.

  For each, the rows equal the API `items` and the header equals "`matched` of `total` tasks".
  The namespace options equal the unfiltered read's namespaces.

  Implement in `frontend/src/lib/catalog/catalog.ts` and `frontend/src/lib/catalog/CatalogScreen.svelte`:
  - the filter bar per the prototype (a real `<label>` for each control; no "New task" button);
  - search debounced by 300 ms;
  - the latest-response-wins sequence number;
  - namespace options from the latest unfiltered page (research R-2).

  Run unit + e2e.

---

## Phase 5: User Story 2 — Recognise what SentaiTask scheduled and open its flow (P1)

This phase follows plan row 4, which also completes US-1's detail (US-1.4–7).

**Goal**: task detail, the SentaiTask origin mark, and a link to the flow in two clicks or fewer.

**Independent test**: `us8-catalog-origin.spec.ts`. A scheduled 3-step flow gives exactly 3
marked rows, and the link opens the flow.

- [ ] T005 [US2] Detail, origin and link (plan row 4; depends on T003). Not [P] with T004, because
  both edit `catalog.ts`. **Gate: e2e needs G-A.**

  **Unit first**, in `frontend/src/lib/catalog/catalog.test.ts`. Three tests:
  1. The origin model: `flowExists:true` gives a link to `?flow=<id>` with the text
     "flow <id> · step <id>"; `false` gives "flow not found" with no link; absent gives no mark.
  2. `recentRuns` absent gives no section; `[]` gives "No runs reported"; a list keeps verbatim
     values and adds no duration.
  3. Detail field set equals the FR-006 list.

  **e2e**:
  - `frontend/tests/us8-catalog-origin.spec.ts`:
    1. `seedFlow` a 3-step integrity-check flow, then `POST /flows/{id}/schedule`;
    2. search `SentaiTask: <id>#` → exactly 3 rows marked "flow <id> · step 01/02/03";
    3. **SC-002**: row click (1) and flow link (2) → the canvas with that flow;
    4. delete the flow (test setup) → "flow not found" with no link;
    5. `finally`: delete the 3 tasks (`deleteNativeTask`) and the flow;
    6. write `evidence/us2-origin.json`.
  - Extend `us7-catalog.spec.ts` test 2 with the detail of 3 tasks (task 4, a SentaiTask task,
    and one with `lastError`), each field equal to `GET /catalog/tasks/{id}`. Plus a deep link to
    `?view=catalog&task=4`.

  Implement:
  - `frontend/src/lib/catalog/CatalogDetail.svelte`: header with name and `class · ID n`; marks;
    field grid; origin; recent runs; no WQM/privilege/GUID/duration.
  - `api.catalogTask(id)` in `frontend/src/lib/api/client.ts`.
  - The detail selection writes `task=<id>` via `goto` (in `+page.svelte`/`CatalogScreen.svelte`).
  - A non-numeric `task` gives "Task not found" with no call.

  Run unit + e2e.

---

## Phase 6: User Story 4 — Suspend and resume a task (P2)

**Goal**: exactly one of Suspend or Resume, disabled while pending, with the result confirmed by
re-read and refusals shown verbatim.

**Independent test**: `us10-catalog-suspend.spec.ts`.

- [ ] T006 [US4] Suspend/resume (plan row 5; depends on T005). **Gate: e2e needs G-A.**

  **Unit first**, in `frontend/src/lib/catalog/catalog.test.ts`. Two tests on the action reducer:
  1. idle → pending (button disabled) → ok (task from body, list re-read requested);
  2. pending → error (reason via `refusalText`, item and list re-read requested); `suspended`
     unavailable → no action offered.

  **e2e**, in `frontend/tests/us10-catalog-suspend.spec.ts`. Two tests, both on a task from a
  seeded and scheduled flow, never an instance task:
  1. Suspend: the button is disabled while pending, then SUSPENDED shows in both detail and row,
     and a fresh `GET /catalog/tasks/{id}` agrees. Resume: active, and a fresh read agrees.
  2. As a temporary operator without `%Admin_Task`, a direct detail link shows "HTTP 403 — no
     reason given". The generated password is never logged, and the user is deleted in
     `finally`.

  Seeded tasks and the flow are removed in `afterAll`. Write `evidence/us4-suspend.json`.

  Implement: `api.setSuspended(id, suspended)` in `frontend/src/lib/api/client.ts`, and the
  actions in `frontend/src/lib/catalog/CatalogDetail.svelte`. There is no automatic retry after a
  401 (research R-5).

  Run unit + e2e.

---

## Phase 7: User Story 5 — Compose flows with declared custom steps (P1)

**Goal**: a *Custom* palette group from the API, and a parameter form generated from the declared
schema. Errors appear on the field through the structured `parameter`, with a step-level fallback.

**Independent test**: `us11-declared-steps.spec.ts`.

- [ ] T007 [US5] Custom group and labels (plan row 6). **Gate: G-B, for visuals and e2e.** The
  unit tests may start before.

  **Unit first**. Three tests:
  - `frontend/src/lib/api/wire.test.ts`:
    1. `fromWireStepTypes` maps `label`, `executor` and `parameters` (the 005 fixture);
    2. a pre-005 catalog (no new fields) still maps, with `label` absent.
  - `frontend/src/lib/flow/document.test.ts`:
    3. grouping puts `executor === 'in-process'` in *Custom* along with legacy `custom`. The other
       types stay in their category groups.

  **e2e**, in `frontend/tests/us11-declared-steps.spec.ts`, test 1: the *Custom* group equals the
  catalog's in-process entries plus legacy `custom` (disabled, "not supported"), with the API
  labels shown.

  Implement:
  - `frontend/src/lib/api/wire.ts`;
  - `frontend/src/lib/flow/document.ts`: `StepTypeInfo.label/executor/parameters`; `stepLabel`
    prefers `label`; `createStep` stores **no** default for declared types (R-7);
    `DEFAULT_PARAMETERS` is kept only for `purge-audit-records` until 005 T002 declares its schema
    (BD-2), then deleted in this task if already present;
  - `frontend/src/lib/palette/Palette.svelte`.

  If an existing e2e asserts a title that the API label changes, adjust only that assertion and
  record it in the commit. No test is removed.

  Run unit + e2e.

- [ ] T008 [US5] Parameter form and errors (plan row 7; depends on T007). **Gate: G-B.**

  **Unit first**, in `frontend/src/lib/flow/params.test.ts`. Five tests:
  1. `ParameterSpec` → field model for each of the 4 types: control, bounds hint, required mark,
     placeholder `default: <value>`, `description` as help.
  2. Writes: `integer` and `number` coerce to `Number`; `boolean` from the checkbox; `string`
     as-is; clearing **removes the key**.
  3. Findings with `parameter` go to the matching field (fixture **with** `parameter`).
  4. Findings without `parameter`, or with a `parameter` the schema lacks (`PARAM_UNKNOWN`), go
     to step level (fixture **without** `parameter`). The message text is never parsed; assert
     the function never reads `message` for routing.
  5. An unknown `type` becomes a read-only row, never a text input.

  **e2e**, in `frontend/tests/us11-declared-steps.spec.ts`, test 2:
  - `storage-headroom-check` shows exactly one field `minFreePercent` (number, 0–100, placeholder
    `default: 10`, description).
  - `db-size-report` shows "takes no parameters".
  - Set 150, save and validate: `PARAM_OUT_OF_RANGE` is shown verbatim **on the field**, which
    requires 005 T008's `parameter` (BD-1). The status bar counts it.
  - Write `evidence/us5-params.json` (field-level vs step-level).

  Implement:
  - `frontend/src/lib/flow/params.ts`;
  - `frontend/src/lib/inspector/ParameterForm.svelte`, with real `<label for>` (002 FR-016);
  - `frontend/src/lib/inspector/Inspector.svelte`: use `ParameterForm` when the type declares
    `parameters`; keep the 002 local field only for `purge-audit-records` while BD-2 is open.

  Run unit + e2e.

---

## Phase 8: User Story 6 — Destructive declared types and legacy `custom` (P2)

**Goal**: the three destructive signals for any destructive type, including the missing typed
confirmation, and the legacy `custom` class read-only.

**Independent test**: `us14-typed-confirmation.spec.ts` and `us12-destructive-legacy.spec.ts`.

- [ ] T009 [US6] Typed confirmation before dispatch (plan row 8a, D-7).
  - **Not blocked on T001.** It uses the existing dialog's visual system.
  - **Release gate for spec 005:** `purge-task-history` may only become `available: true`
    (005 T016) after this task is merged **with its e2e green**. The e2e runs under G-C's
    temporary, uncommitted flip, so there is no cycle: T009 merged (e2e green) → 005 T016 commits
    the flip. It may be pulled forward and done before T002.
  - It edits `client.ts`, so it runs between other `client.ts` tasks, never concurrently.
  - **Gate: e2e needs G-C.** The unit tests are ungated.

  **Unit first**, in `frontend/src/lib/flow/document.test.ts`. Two tests on
  `confirmationsFor(steps, registry, typed)`:
  1. One entry `{stepId, typedName}` per step whose registry entry is `destructive: true`, and
     none for other steps.
  2. The dialog is incomplete until every destructive step has a non-empty value. Matching is
     **not** checked locally; the backend decides.

  **e2e**, in `frontend/tests/us14-typed-confirmation.spec.ts`. One test, run when G-C holds:
  1. Build a flow with a `purge-task-history` step, then Run.
  2. The dialog shows one required field labelled with the step and the value to type (the
     database directory, or the namespace).
  3. A wrong value → the 428 `detail` is shown verbatim, and the dialog stays open.
  4. The right value → dispatched, and the run screen opens.
  5. `finally`: cancel the run and delete the flow.

  Implement:
  - `frontend/src/lib/shell/DispatchDialog.svelte`: one `<label>` and `<input required>` per
    destructive step;
  - `frontend/src/lib/flow/editor.svelte.ts`: `dispatch(password, confirmations)`;
  - `frontend/src/lib/api/client.ts`: `api.dispatch` body with `confirmations`.

  Existing `us4` dispatch tests (non-destructive) must stay green. Run unit + e2e.

- [ ] T010 [US6] Declared destructive node and legacy `custom` read-only (plan row 8b; depends on
  T008 and T009). **Gate: G-B.**

  **e2e first**, in `frontend/tests/us12-destructive-legacy.spec.ts`. One test:
  - `purge-task-history` dropped from the *Custom* group shows the hazard band, the
    `destructive-seal` and the category left border, at fit and zoomed-out views.
  - The inspector destructive block is present.
  - A seeded flow with a legacy `custom` step shows "not supported". The class is read-only text,
    and `getByLabel('Custom class')` finds **no input**.

  Implement:
  - `frontend/src/lib/inspector/Inspector.svelte`: remove the custom-class `<input>` and
    `setText('customClass')`; show the class read-only with the reason. Declared destructive
    types use the generic consequence sentence.
  - `frontend/src/lib/canvas/StepNode.svelte` only if the prototype requires a change (the signals
    already come from the registry).

  Run unit + e2e.

---

## Phase 9: Polish — theming parity and evidence

- [ ] T011 Theming parity and evidence (plan row 9). The Part A half depends on T006; the Part B
  half depends on T010.

  **e2e**, in `frontend/tests/us13-management-theming.spec.ts`. One test:
  - paired 1440×900 dark/light screenshots of the catalog, with a destructive row selected, and
    of the parameter form with one field error;
  - the same structural, string and contrast assertions as `us6-theming.spec.ts`;
  - `evidence/sc008-*.png`.

  **SC-003 timing** (in `us9-catalog-filters.spec.ts`, or a tagged run):
  - seed about 150 tasks by scheduling a few large integrity-check flows;
  - catalog first rows < 3 s and a filter update < 2 s, over 3 runs;
  - write `evidence/sc003-timing.txt`;
  - delete every seeded task and flow, and check the `%SYS.Task` count returns to its value
    before the run.

  **Docs**:
  - `README.md` gains a section on the catalog screen, custom steps, and the BD status;
  - `specs/007-canvas-management-screens/evidence/README.md` records the test counts
    (unit ~81, e2e 24, 0 removed) and the SC-001…SC-008 results.

  Run unit + e2e.

**Cut order if time runs short**:
1. Part B tasks T007, T008 and T010 wait for T001 and 005, without affecting Part A.
2. T011's Part B half follows them.
3. T004's namespace filter may ship after search and state.

**Never cut**:
- T002, T003, T005 and T006 (Part A core);
- **T009, as long as 005 ships `purge-task-history`.**

---

## Cross-spec dependencies

**Implementation order: 006 → 005 → 007.** 007's unit tests and ungated code can start at any
time, using contract fixtures.

| Backend event | Unblocks in 007 |
|---|---|
| 006 T001–T005 on the container | G-A: e2e of T002–T006 (Part A). T011 Part A half |
| 005 T001–T008 + T013 on the container, and T001 prototype done | G-B: T007, T008, T010 (visuals + e2e) |
| 005 T008 with `parameter` in findings (BD-1) | SC-005's field-level part of T008. Without it, T008's e2e records step-level and SC-005 is **not met** |
| 005 T002 declares `purge-audit-records` parameters (BD-2) | T007/T008 delete the local `DEFAULT_PARAMETERS`/`PARAMETER_FIELDS` |
| **007 T009 merged** | **005 T016 may flip `purge-task-history` to `available: true`** (the reverse gate) |
| 005 T013 on the container + temporary flip (G-C) | e2e of T009 and T010 (T009 must be green before 005 T016 commits the flip) |

- BD-1 and BD-2 live in **005's `tasks.md`** (added by T000). BD-3 and BD-4 are the deployment
  gates G-A and G-B.
- 005 T014 owns any adjustment of the existing `us1` palette e2e caused by switch-journal becoming
  available.

## Dependencies & Execution Order

```
T000 (docs) ─ first
T001 (design) ─────────────────────────────────┐ (G-B)
T002 ─▶ T003 ─┬─▶ T004 ─┐                      │
              └─▶ T005 ─┴─▶ T006 ─▶ T011(A)     │
T009 (ungated code; client.ts sequenced) ─┐    ▼
                                           ├─▶ T007 ─▶ T008 ─▶ T010 ─▶ T011(B)
```

**Same file, sequential**:

| File | Order |
|---|---|
| `client.ts` | T003 → T005 → T006, with T009 before or after, never concurrently |
| `CatalogScreen.svelte` / `catalog.ts` | T002 → T003 → T004 → T005 → T006 |
| `Inspector.svelte` | T008 → T010 |
| `document.ts` | T007 → T009 (or T009 first) |

## Parallel Opportunities

- **T001** (design) runs alongside all of T002–T006.
- **T009** runs alongside T004 once T003's `client.ts` edit is merged, and vice versa for T005.
  Only one `client.ts` edit is in flight at a time.

Example, after T003:

```text
Designer: T001
Dev A:    T004 → T005 → T006
Dev B:    T009 (after T005's client.ts edit, or before T003)
```

## Implementation Strategy

1. **MVP = T000 + US1 (T002–T003)**: the catalog is reachable, and its values are true.
2. **+ US3 (T004)** makes it findable, **+ US2 (T005)** adds the origin and the flow jump, and
   **+ US4 (T006)** adds suspend/resume. Part A is then complete.
3. **T009** lands before 005 releases `purge-task-history`.
4. **Part B** (T007 → T008 → T010) comes once the prototype and 005 are on the container.
5. **T011** adds the evidence.

Each step leaves unit and e2e green, adds no backend change, and removes no test.
