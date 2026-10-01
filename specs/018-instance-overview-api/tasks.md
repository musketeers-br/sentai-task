# Tasks: Instance Overview API — Every Contest Area Readable on Demand

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD, Constitution V). Backend `%UnitTest` only, through the full suite:

```sh
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
EOF
```

There is no single-class run (AGENTS.md). The platform is scripted with
`sentai.unittest.AdminApiDouble` (`Enable`, `Script(path, method, status, location, body)`,
`Reset`; hits counted in `^sentaiTestDouble("getcount", path)`). `ScriptDown` works per target
`baseUrl` only: a silent **primary** read is scripted as `Script(path, "GET", 0)` (status 0, no
body), which `TaskService.PlatformRead` reports as unreachable. New test classes sit flat under `tests/sentai/unittest/overview/`,
package `sentai.unittest.overview`, extending `sentai.unittest.SentaiTestCase`.

**Hard rules**:
- No platform path, query string or field name is ever taken from a request (FR-002): area ids
  select from `sentai.overview.Areas`; anything else is refused before any call.
- Every platform call uses `sentai.rest.Dispatcher.CurrentToken()`; refusals keep the platform's
  HTTP status and `platformStatus` verbatim (`TaskService.Refusal`). Nothing is cached.
- Only allow-listed fields leave the product (data-model §2). Never copy `ID` (web sessions),
  `DeleteID` (locks) or `CSPSessionID` (process read).
- No change to `src/sentai/registry/StepType.cls` (clarification Q4).
- Never hand-edit a `Storage` block. A class is only saved when the instance has it (`zpm load`).
- The suite stays green at every task end; record the count in `evidence/README.md` at T031.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[external]**: needs an action outside the repository or a human session; never blocks
  `Implemented`

---

## Phase 1: Setup

- [x] T001 Baseline in `specs/018-instance-overview-api/evidence/README.md`: suite count on this branch before any change (expected 268 methods, `All PASSED`), date, container image, and a table header for the quickstart scenarios (scenario, command, result, date). No credential in the file.
- [x] T002 [P] Create the package folders `src/sentai/overview/` and `tests/sentai/unittest/overview/` (a first class in each arrives in T004/T003); confirm `module.xml`'s `<Resource>`/`<UnitTest Name="/tests" Package="sentai.unittest">` already picks them up without edits (the module loads `src` by directory).

---

## Phase 2: User Story 1 — Read one instance resource area on demand (P1) 🎯 MVP

**Goal**: `GET /overview/readings/{area}` for the seven instance areas. The compiled area table
(T003–T004) is built first because every later story selects from it; it is part of this increment,
not a deliverable of its own (Constitution V).

**Independent test**: quickstart scenarios 1–3 and 10 on the dev stack; `AreaTableTest`,
`ReadingsTest` and the readings part of `OverviewEndpointTest` green.

### The area table

- [x] T003 [P] [US1] `tests/sentai/unittest/overview/AreaTableTest.cls`: `sentai.overview.Areas.All()` returns exactly the 11 ids of data-model §1 in that order, with `group` `instance`/`report`; `IsReading(id)` true only for the seven instance ids; `StepTypeOf(id)` returns the four report mappings and "" for the rest; every non-empty `StepTypeOf` is a catalog type whose `sentai.registry.StepType.GetExecutor` is `platform-read` and `IsInstalled`; `Lookup("../api/admin/info")`, `Lookup("")`, `Lookup("Processes")` (case) return "" (unknown).
- [x] T004 [US1] `src/sentai/overview/Areas.cls` (plan D-1): `XData Table` (JSON array of `{id, group, reading, stepType}`) and class methods `All()`, `Lookup(id)`, `IsReading(id)`, `StepTypeOf(id)`, parsing the XData once per call the way `sentai.registry.StepType.GetCatalog()` does. T003 passes.

### Tests first

- [x] T005 [P] [US1] `tests/sentai/unittest/overview/ReadingsTest.cls`, platform scripted per reading with answers shaped like the probe (research R-1): for each of the seven areas, `sentai.overview.Readings.Read(area, token)` calls exactly the paths of research R-1 and returns `{httpStatus: 200, body: Reading}` with `area`, `readAt`, `columns`, `rows` (data-model §2); rows carry only allow-listed fields — a scripted row that also has `ID`, `DeleteID`, `CSPSessionID`, `Password` loses them; a missing field is `null`, not `0`; `memory` rows have `SMHUsedPercent` (`2809140/3342336` → `84.0`; `SMHAllocated` 0 → null) and `computed` = `["SMHUsedPercent"]`; `activity` has `rows` from system-resources and `parts.systemUsage`/`parts.dashboard`; `licenses` has `rows` = `UsageByProcess`, `parts.summary`, `parts.byUser` and no `ConnectionList`; every nested object (`parts.*`, `BusyProcesses` entries, license rows) holds only the fields data-model §2 lists — a scripted extra field inside each nested object is dropped.
- [x] T006 [P] [US1] Same file, failure cases: a scripted 403 with a status object → `{httpStatus: 403, problem}` whose `platformStatus` equals the scripted object; a 200 whose `status.errors` is non-empty → refused (502 per `TaskService.Refusal`) with the platform's summary; a path scripted with status 0 → 502 `PLATFORM_UNREACHABLE`; for `activity`, one of its three reads refused → the whole reading is that refusal (no partial reading); two consecutive `Read` calls produce two platform calls (count scripted hits).
- [x] T007 [P] [US1] `tests/sentai/unittest/rest/OverviewEndpointTest.cls` (readings part): `GET /overview/readings/processes` → 200 body of T005; `…/readings/security`, `…/readings/nope`, `…/readings/..%2Fapi%2Fadmin%2Finfo` → 404 `UNKNOWN_READING` with **zero** scripted platform hits; `…/readings/processes?target=iris-target` → 400 `OVERVIEW_PRIMARY_ONLY` with zero hits; no Bearer → 401 (existing `OnPreDispatch`). Follow the request/response harness used by `tests/sentai/unittest/rest/CatalogTasksTest.cls`.

### Implementation

- [x] T008 [US1] `src/sentai/overview/Readings.cls` (plan D-2): `Read(area, token) As %DynamicObject` → outcome `{httpStatus, body|problem}`; one private method per area with its fixed paths; each platform read through `sentai.catalog.TaskService.PlatformRead(path, token)` and failures through `TaskService.Refusal(read)`; a read with `status.errors` non-empty is a refusal; rows copied with `sentai.steps.reports.Report.Pick(row, $LB(...allow-list...))` then every allow-listed name absent in the source set to JSON null; `SMHUsedPercent` computed as `$FN(SMHUsed/SMHAllocated*100,"",1)` when `SMHAllocated > 0`; `readAt` = `$ZDT($ZTS,3,,3)` UTC ISO form used elsewhere in the product. T005, T006 pass.
- [x] T009 [US1] `src/sentai/rest/Dispatcher.cls`: route `<Route Url="/overview/readings/:area" Method="GET" Call="ReadOverviewReading"/>` and a thin handler: refuse any `target` in `%request` with `WriteProblem(400, "Bad Request", "OVERVIEW_PRIMARY_ONLY: overview readings are for the primary instance only")`; refuse `'Areas.IsReading(area)` with `WriteProblem(404, "Not Found", "UNKNOWN_READING: …")`; else `WriteOutcome(Readings.Read(area, ..CurrentToken()))`. Add the shared `OverviewTargetRefused()` helper used by every overview handler. T007 passes.
- [x] T010 [US1] Run quickstart scenarios 1–3 and 10 against the dev stack (`zpm load` first); record results and the slowest reading time (SC-001 < 2 s) in `evidence/README.md`.

**Checkpoint**: MVP — the operating-system area is readable through the product.

---

## Phase 3: User Story 2 — One summary of every area (P1)

**Goal**: `GET /overview` with 11 independent entries (clarification Q1: counts only).

**Independent test**: quickstart 4–5; `SummaryTest` and `OverviewSecrecyTest` green.

### Tests first

- [x] T011 [P] [US2] `tests/sentai/unittest/overview/SummaryTest.cls`: all 11 reads scripted OK → `OverviewService.Summary(token)` returns `areas` with the 11 ids in data-model §1 order, each `outcome: "ok"`, `readAt`, `stepType` from `Areas`, and the headlines of research R-3 computed from the scripted answers (processes `count` + `busiest` by max `Commands`; locks `count`; memory `usedPercent` from the `Total` row and `mostUsed` among rows with `SMHAllocated > 0`; activity `uptime`, `lastBackup`, `globalRefsPerSecond`, `busyProcesses` counting entries with a non-empty `Process`; devices `count`; licenses `inUse`/`authorized` from the `Summary` rows by their `LicenseUnitUse` label (trimmed), `Local` as number; web-sessions `count`; security `accounts` and `enabledAccounts`; web-apps `count`; alerts `seriousAlerts`/`applicationErrors`; secrets `collections`). Exactly 10 distinct platform paths are hit, each once; `dashboard/main` (hit count 1) feeds both `activity` and `alerts`. No report class is called (no `security/user?name=` or `wallet/secrets` hit).
- [x] T012 [P] [US2] Same file, independence: `security/users` scripted 403 → `security` entry `refused` with `problem.httpStatus` 403 and `platformStatus` verbatim, the other 10 `ok`; `devices` scripted with status 0 → entry `unreachable` with `problem.httpStatus` 0 and the product's `PLATFORM_UNREACHABLE` text, the others `ok`; `dashboard/main` refused → both `activity` and `alerts` refused, others ok; an empty `web-sessions` list → `ok` with `count: 0`; a missing `Total` row → memory `usedPercent: null`, still `ok`.
- [x] T013 [P] [US2] `tests/sentai/unittest/overview/OverviewSecrecyTest.cls` (SC-006): script every read with extra fields `Password`, `PasswordHash`, `access_token`, `ID`, `DeleteID`, `CSPSessionID`, `Value` carrying a marker string, **at the top level and inside every nested object** (`dashboard.Performance`, `dashboard.SystemUsage`, `license-usage.UsageByProcess[]`, `UsageByUser[]`, `ConnectionList[]`, `system-usage`); call every overview entry point built so far (readings, summary; extended in T018 and T024) and assert the marker never appears in any answer's `%ToJSON()`.
- [x] T014 [P] [US2] `OverviewEndpointTest` additions: `GET /overview` → 200 with 11 entries even when every read is refused; `GET /overview?target=x` → 400 `OVERVIEW_PRIMARY_ONLY`, zero hits.

### Implementation

- [x] T015 [US2] `src/sentai/overview/OverviewService.cls` (plan D-3, D-8): `Summary(token) As %DynamicObject`: make the 10 distinct reads once each (11 areas; `dashboard/main` feeds two) in series with `TaskService.PlatformRead`, build each entry `{area, group, outcome, readAt, headline, problem, stepType}` (data-model §3; httpStatus 0 → `unreachable`; non-200 or `status.errors` → `refused` with `TaskService.Problem(...)` fields), and one pure class method `Headline<Area>(result) As %DynamicObject` per area (unit-testable without the double). T011, T012 pass.
- [x] T016 [US2] `Dispatcher.cls`: route `<Route Url="/overview" Method="GET" Call="ReadOverview"/>` → target refusal, then `WriteJSON(200, OverviewService.Summary(..CurrentToken()))`. T013, T014 pass.
- [x] T017 [US2] Quickstart 4 (time < 3 s, SC-002) as `_SYSTEM`, and 5 as an operator holding only the `SentaiDemo` role (created by `scripts/demo/demo-account.script`, spec 011; create a temporary `ovw-test` account with that role in `%SYS`, run, delete it; SC-003). Record both in `evidence/README.md` with the per-area outcomes as a table (which areas that role was refused and which it could read, as observed), and check that `security` is among the refused and that every refused entry carries `platformStatus`. No credentials.

---

## Phase 4: User Story 3 — Run a spec 013 report without a flow (P1)

**Goal**: `POST /overview/reports/{stepType}` with the step's own code.

**Independent test**: quickstart 6–7; `OnDemandReportTest` green.

### Tests first

- [x] T018 [P] [US3] `tests/sentai/unittest/overview/OnDemandReportTest.cls`: for each of `security-posture-report`, `web-app-inventory`, `system-alerts-check`, `secrets-inventory`, with scripted answers modelled on `tests/sentai/unittest/steps/ReportSecurityTest.cls` and `ReportSystemAlertsTest.cls` (and equivalent minimal answers for web apps and wallet), `OverviewService.RunReport(type, parameters, token)` returns `{stepType, state, failureReason, report, ranAt}` whose `report.findings` equals `sentai.dispatch.ReadExecutor.Build(type, parameters, Reader.For("", token), .r)`'s findings (same rule, severity, item, order) and `state` is `completed`/`failed` exactly when `Build` returns OK/error, `failureReason` = the error text; the number of `sentai.model.Run`, `StepRun` and `LogEntry` rows is unchanged after each call (`SELECT COUNT(*)` before/after); a report larger than 8,000 characters is **not** truncated (no `truncated` key). Extend `OverviewSecrecyTest` (T013) to call `RunReport` for the four types.
- [x] T019 [P] [US3] Same file, refusals without a platform call: `integrity-check` → `STEP_TYPE_NOT_A_REPORT`; `nope` → `UNKNOWN_STEP_TYPE`; `system-alerts-check` with `{"maxSeriousAlerts": -1}` and with `{"maxSeriousAlerts": "x"}` → the validator's `PARAM_*` codes exactly as `FlowValidator.DeclaredStepFindings` gives them for a flow step with those parameters; zero scripted hits in all three cases. A scripted 403 on `security/users` → `state: failed`, `failureReason` containing the platform's summary verbatim (the `Reader` text).
- [x] T020 [P] [US3] `OverviewEndpointTest` additions: `POST /overview/reports/web-app-inventory` `{}` → 200; `…/reports/integrity-check` → 422 `STEP_TYPE_NOT_A_REPORT`; `…/reports/nope` → 404 `UNKNOWN_STEP_TYPE`; parameter errors → 422 `{errors, warnings}`; body with `target` → 400 `OVERVIEW_PRIMARY_ONLY`; `GET /runs` count unchanged.

### Implementation

- [x] T021 [US3] `OverviewService.RunReport(type, parameters, token)` (plan D-4, research R-6): `StepType.IsKnownType` → else 404 outcome; executor `platform-read` → else 422; `FlowValidator.DeclaredStepFindings("ondemand", type, StepType.GetParameterSchema(type), parameters, StepType.GetTargetClass(type), errors)` → errors non-empty → 422 `FlowValidator.Report(errors, [])`; else `ReadExecutor.Build(type, parameters, sentai.steps.reports.Reader.For("", token), .report)`; set `report.instance = "local"` as `ReadExecutor.Run` does; answer 200. T018, T019 pass.
- [x] T022 [US3] `Dispatcher.cls`: route `<Route Url="/overview/reports/:stepType" Method="POST" Call="RunOverviewReport"/>` → target refusal (query and body), `ReadJSONBody().parameters`, `WriteOutcome(OverviewService.RunReport(...))`. T020 passes.
- [x] T023 [US3] Quickstart 6 (SC-004: on-demand vs one-step run of `web-app-inventory`, same findings; confirm the stored step result has no `truncated` key and no `summary.findingsOmitted` — if it has, the comparison is outside SC-004's scope and is recorded as such; run list unchanged by the on-demand call) and 7. Record in `evidence/README.md`.

---

## Phase 5: User Story 4 — Turn a reading into a scheduled check (P2)

**Goal**: `POST /overview/areas/{area}/flow` creates an ordinary one-step flow.

**Independent test**: quickstart 8–9; `AreaFlowTest` green.

### Tests first

- [x] T024 [P] [US4] `tests/sentai/unittest/overview/AreaFlowTest.cls` (flows with names prefixed `Check: ` created by the test are deleted in `OnAfterOneTest`): `AreaFlow.Definition("secrets", {}, token)` → a definition with name `Check: Secrets inventory`, `defaultCategory`, one step `"01"` of type `secrets-inventory`, `taskName` = catalog label, namespace `%SYS`, parameters as given, geometry `{"01": {"x": 40, "y": 160}}`; `AreaFlow.Save(def, user, token)` → `{flowId, validation}` where `validation` = `FlowValidator.Validate(flowId, token)` with no errors when `wqm-categories` is scripted with `Default`; `sentai.overview.AreaFlow` references no `sentai.rest.*` class (assert by reading its compiled source in `%Dictionary.CompiledMethod`); a second call names the flow `Check: Secrets inventory (2)`; `wqm-categories` scripted without `Default` → the first listed category is used; `wqm-categories` refused → `Default` is used and validation reports what it reports (no special case); `processes` → 409 `AREA_HAS_NO_STEP_TYPE`, no flow created; `nope` → 404 `UNKNOWN_AREA`; invalid parameters → 422 with `PARAM_*`, no flow created. Extend `OverviewSecrecyTest` with this entry point.
- [x] T025 [P] [US4] `OverviewEndpointTest` additions: `POST /overview/areas/secrets/flow` → 201; `…/areas/processes/flow` → 409; body with `target` → 400; then `POST /flows/{id}/schedule` on the new flow is accepted by the existing handler (scripted task create) — no change to scheduling code.

### Implementation

- [x] T026 [US4] `src/sentai/overview/AreaFlow.cls` (plan D-5, research R-8): application layer only: `Definition(area, parameters, token)` returns an outcome — `Areas.Lookup`/`StepTypeOf` checks (404/409), parameter validation as in T021 (422), category from `sentai.wqm.CategoryService.List(token)` (`Default` if listed, else first, else `Default`), unique name by probing `sentai.model.Flow.NameIndexExists` with ` (n)` suffixes; `Save(def, user, token)` calls `sentai.model.Flow.SaveGraph(def, "", 0, user, .id)` and returns `{flowId, validation: FlowValidator.Validate(id, token)}`. No call to `sentai.rest.*`. T024 passes.
- [x] T027 [US4] `Dispatcher.cls`: route `<Route Url="/overview/areas/:area/flow" Method="POST" Call="CreateOverviewFlow"/>` → target refusal; `AreaFlow.Definition(...)` (write its refusal outcome as is); `..ValidateStructural(def)` → 422 on errors, as `CreateFlow` does; `AreaFlow.Save(def, ..CurrentUser(), ..CurrentToken())`; answer 201 `{flow: ..ShapeFlow(flow, 1), validation}`. T025 passes.
- [x] T028 [US4] Quickstart 8 (SC-007: create from `secrets`, schedule a minute ahead with the existing endpoint, the scheduled run completes with the secrets inventory report; unschedule and delete the flow afterwards) and 9. Record in `evidence/README.md`.

---

## Phase 6: User Story 5 — Suspend, resume or terminate a process (P3, gated)

**Goal**: process actions only if the platform contract proves usable (clarification Q2).
**Nothing in Phases 2–5 depends on this phase.**

### Spike (FR-019)

- [x] T029 [US5] Spike on the dev stack (research R-7): start a disposable process in `USER` (`docker exec … iris session iris -U USER` with `job ##class(%SYSTEM.Process)…` or a `JOB` of a `hang 600` loop — whichever the spike shows works; record which), read it with `GET /api/admin/v2/process?id=<pid>`; for `suspend`, `resume`, `terminate` try bodies `{"pid": n}`, `{"Pid": n}`, `{"id": n}` and query `?id=n`; record request, status, body, and the re-read state; repeat terminate as a temporary operator without `%Admin_Operate` (created and deleted by the spike) to capture the refusal. Write `specs/018-instance-overview-api/evidence/01-process-suspend.json`, `02-process-resume.json`, `03-process-terminate.json`, `04-process-refused.json` in spec 001's envelope (`specs/001-validate-async-job-contract/contracts/evidence-envelope.md`), tokens and passwords redacted, and a verdict paragraph in `evidence/README.md`. Fill the "platform request body" line of `contracts/api-delta.md`. **Stop and flag** if no body shape works: then skip T030–T033 and do T034 only.

### Tests first (only if T029 passes)

- [x] T030 [P] [US5] `tests/sentai/unittest/overview/ProcessActionTest.cls`: `ProcessActions.Act(pid, "terminate", "", user, token)` and with a confirmation other than the pid → 428 `CONFIRMATION_REQUIRED`, zero platform hits, zero `sentai.model.ProcessAction` rows; with `confirmation = pid` and the platform scripted per T029 → the platform's answer returned verbatim, the process re-read with `GET /v2/process?id=` (allow-listed, no `CSPSessionID`), one row with operator, pid, action, httpStatus, `accepted` true; scripted 403 → the refusal verbatim and one row with `accepted` false and `platformStatus` verbatim; `suspend`/`resume` need no confirmation; an action outside the three → 404 without a call; `ProcessActions.List(50)` newest first; the product never refuses a pid on its own (a scripted `CanBeTerminated: false` row still sends the request). Extend `OverviewSecrecyTest` with this entry point.

### Implementation (only if T029 passes)

- [x] T031 [US5] `src/sentai/model/ProcessAction.cls`: persistent, properties of data-model §5, index on `at`, no update/delete method; storage generated by `zpm load`.
- [x] T032 [US5] `src/sentai/overview/ProcessActions.cls`: `Act(pid, action, confirmation, user, token)` and `List(limit)`, platform body as recorded by T029, confirmation check before any call, one `ProcessAction` row per call that reached the platform. T030 passes.
- [x] T033 [US5] `Dispatcher.cls`: routes `POST /overview/processes/:pid/:action` (action ∈ suspend, resume, terminate; `pid` must be a positive integer, else 400) and `GET /overview/process-actions?limit=1..200`; target refusal; `WriteOutcome`. Add endpoint cases to `OverviewEndpointTest`. Run quickstart 11 on a disposable process and record it (SC-008).

### If the spike fails

- [x] T034 [US5] *Not needed — the T029 spike passed (evidence/README.md); T030–T033 were built.* Only if T029 stopped: add a *Process actions (spec 018)* entry to `docs/limitations.md` saying which action is missing and what the spike observed (link the evidence), mark T030–T033 as not built in the spec's `**Status note**`, and leave no process route in `Dispatcher.cls` (FR-023).

---

## Phase 7: Polish and cross-cutting

- [x] T035 [P] `specs/002-canvas-ui/contracts/openapi.yaml`: the routes of `contracts/api-delta.md` and schemas `Summary`, `AreaEntry`, `Reading`, `OnDemandReport`, `ProcessAction` (the last only if T033 landed).
- [x] T036 [P] `README.md`: API reference section *Instance overview* (routes, the area table, headlines and their sources, primary-only), and the *Contest areas covered* table rows for **Operating system** (processes, locks, shared memory, devices, licenses, web sessions — "instance resources; the management API reports no host CPU or memory") and the four report areas ("on demand, or scheduled as a flow"). `docs/limitations.md`: *Instance overview (spec 018)* — primary only, no host CPU/memory/console log (research R-2), license headline source (research R-3), counts not findings in the summary, web session ids never returned.
- [x] T037 Full regression: the suite (record the new total, `All PASSED`), the frontend unit tests and `npm run check` unchanged (no frontend change expected), and the quickstart table complete in `evidence/README.md`.
- [x] T038 Clean-up: delete flows named `Check: …` and the temporary accounts created by T017/T029, list what was removed in `evidence/README.md`; set the spec's `**Status**` per AGENTS.md (`Implemented` when every task is checked, T034 or T030–T033 being the two exclusive branches) and run `bash scripts/check-spec-status.sh`.

---

## Dependencies & execution order

- **Phase 1 → US1.** T004 (area table, first part of US1) blocks every later story.
- **US1 (Phase 2)** has no story dependency and is the MVP.
- **US2 (Phase 3)** reuses `Readings`' allow-lists only through the headline functions' inputs; it
  can start after T004 in parallel with US1, but T013's secrecy scan grows as T018/T024/T030 land.
- **US3 (Phase 4)** depends only on T004 (the report areas' step types).
- **US4 (Phase 5)** depends on T004 and on the parameter check written in T021 (reuse, not a copy).
- **US5 (Phase 6)**: T029 first; T030–T033 only if it passes, otherwise T034. No other phase depends
  on it (FR-019).
- **Polish** after the stories that ship.

Every `Dispatcher.cls` task (T009, T016, T022, T027, T033) touches the same file: run them in
sequence, never in parallel.

## Parallel examples

- After T004: T005, T006, T007 (US1 tests), T011–T014 (US2 tests) and T018–T020 (US3 tests) are
  all different files and can be written together.
- Within US1: T005 and T006 share `ReadingsTest.cls` — one author, or sequence them.
- Polish: T035 and T036 in parallel.

## Implementation strategy

1. **MVP (the contest's weakest area)**: Phases 1–2 → `GET /overview/readings/*` works; spec 019 can
   build its detail views against it.
2. **Overview screen unblocked**: Phase 3 → spec 019's landing screen has its one call.
3. **Report areas visible**: Phase 4 → the four report cards work.
4. **Orchestration hook**: Phase 5 → *Schedule this check*.
5. **Management action**: Phase 6, only if the spike passes; if the calendar is short, stop after
   Phase 5 — T034 still documents the gap.
6. Phase 7, then `/speckit-analyze` before opening the pull request.
