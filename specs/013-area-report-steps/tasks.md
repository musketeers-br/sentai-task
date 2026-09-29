# Tasks: Area Report Steps

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD). Backend `%UnitTest` under the `AdminApiDouble` (scripted answers per
path and base URL), run with `zpm "test sentai-task -only"` after `LoadDir` of `src` and `tests`;
`git status` after every container-side run. Frontend vitest; Playwright `us27-` against the dev
stack with `iris-target` up.

**Hard rules**: only `GET`s on the management API; allow-listed fields only (plan D-5); findings
never truncated; platform text verbatim; no secret value, password or hash in any result, log or
evidence; e2e flows use the prefix `us27-`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [X] T001 Evidence spike on the dev stack, recorded in `specs/013-area-report-steps/evidence/t001-reads.md` (answers trimmed, no secrets): (a) the answer shape of every call in research R-1, including `wallet/secrets?collection=` on a temporary collection `SentaiT001` with one secret (then delete it; R-5); (b) the privilege each read needs, for `_SYSTEM`, an `%Admin_Manage`/`%Admin_Operate` operator and the spec 011 demo role if it exists (R-2); (c) `SeriousAlerts` after `Monitor.Clear()` and after an instance restart, and whether an alert-state field exists (R-4). Update data-model §2 and plan D-5/D-7 with what is found.
- [X] T002 [P] Baseline counts (backend, unit, e2e) in `evidence/README.md`.

---

## Phase 2: Foundational — executor, registry, result panel (blocks all stories)

**Independent test**: us27 case A — a `system-alerts-check` step runs locally and its result opens.

### Tests first

- [X] T003 [P] `tests/sentai/unittest/ReadExecutorTest.cls`: a `platform-read` step goes `queued → running → completed` with the class's report as result and `executedAs` = the run's dispatcher; on a target it uses the target's base URL and token and `executedAs` = the target subject; a report class error fails the step with the text verbatim and keeps the report; a cancel before the worker ends wins (the worker records nothing); an overdue step is failed by `SweepTimeouts`; `FitResult(json, "summary,findings")` cuts details first and never findings (plan D-3).
- [X] T004 [P] Registry tests in the existing registry test class: the four types are known, available, non-destructive, `remoteCapable`; `IsInstalled` true for a `Report` subclass, false for a class that is not one; `GetExecutor` = `platform-read`. Validator tests: `PARAM_TYPE_MISMATCH` for `failOnFindings: "yes"`, `PARAM_OUT_OF_RANGE` for `maxSeriousAlerts: -1`; a remote `platform-read` step raises no `STEP_TYPE_NOT_REMOTE_CAPABLE`.
- [X] T005 [P] `tests/sentai/unittest/ReportSystemAlertsTest.cls`: scripted dashboard answers: all normal and 0 alerts → completes; serious alerts over threshold → fails naming it; `LockTable: "Troubled"` → `STATUS_NOT_NORMAL`; unknown status string → not normal; `requireNormalStatus: false` ignores statuses; 403 → fails verbatim.
- [X] T006 [P] `frontend/src/lib/run/result.test.ts` (report detection, severity order, labels) and palette tests (groups *Security* and *Monitoring*, `platform-read` not under *Custom*); `frontend/tests/us27-area-steps.spec.ts` case A.

### Implementation

- [X] T007 `sentai.steps.reports.Report` (abstract, finding helpers, allow-list copy), `Reader` (bound `Get(path)` over `AdminApiClient`), `sentai.dispatch.ReadExecutor`, the `FitResult` overload, `WaveDispatcher.StartStep` branch and `SweepTimeouts` condition, `StepType` changes (entries, `remoteCapable`, `IsInstalled`). T003, T004 pass.
- [X] T008 `sentai.steps.reports.SystemAlerts` (plan D-7, per T001 findings). T005 passes.
- [X] T009 Frontend: wire (`executor`, categories, `result`), `document.ts` groups, `result.ts`, `ResultPanel.svelte`, `ReportView.svelte`, **Result** in `RunNode.svelte` for every terminal step with a result (plan D-9). T006 passes; us4/us11/us16 unchanged.

**Checkpoint**: the executor works end to end and every stored result is visible in the canvas.

---

## Phase 3: User Story 1 — Security posture report (P1)

- [X] T010 [P] [US1] `ReportSecurityPostureTest`: users + per-user roles + services + audit scripted → findings `ALL_ROLE_HOLDER`, `UNAUTHENTICATED_SERVICE` (enabled only), `AUDIT_DISABLED`; one user's read refused → `ROLES_NOT_READABLE` and the step completes; every per-user read refused → the step fails with the first refusal verbatim (spec edge case "unless every read failed"); the list refused → fails verbatim; 250 enabled users → 200 role reads and `ROLES_CAP_REACHED`; `failOnFindings` true with a high finding → fails and the report is kept; an answer with extra fields (`Password`, `PasswordHash`) → absent from the result.
- [X] T011 [US1] `sentai.steps.reports.SecurityPosture` and its registry entry. T010 passes.
- [X] T012 [US1] us27 case B: the report locally and on `iris-target`, as `_SYSTEM` (completes, `_SYSTEM` listed as `ALL_ROLE_HOLDER`) and as a limited operator created and removed by the test through `tests/iris.ts` (fails with 403 verbatim).

---

## Phase 4: User Story 2 — Web application inventory (P2)

- [X] T013 [P] [US2] `ReportWebAppInventoryTest`: rules of data-model §2 with the probe's list (research R-1): `/api/monitor` → `ANONYMOUS_REST_ENDPOINT`; `/csp/sentai` → `ANONYMOUS_APPLICATION`; `/csp/sys` (system) → no finding; disabled app → no finding; resource set → no finding.
- [X] T014 [US2] `sentai.steps.reports.WebAppInventory` and its entry. T013 passes. us27 case C.

---

## Phase 5: User Story 4 — Secrets inventory (P3)

- [X] T015 [P] [US4] `ReportSecretsInventoryTest` (empty wallet → completes empty; collection without use resource → `UNPROTECTED_COLLECTION`; an answer carrying `Value`/`Secret` fields → dropped) and `ResultSecrecyTest` (runs every report type under the double with a sentinel secret and password in the scripted answers; scans the stored results and log entries: 0 occurrences — SC-004).
- [X] T016 [US4] `sentai.steps.reports.SecretsInventory` and its entry. T015 passes. us27 case D with a temporary collection created and deleted by the test.

---

## Phase 6: User Story 3 — Alerts check as a gate (P2)

- [X] T017 [US3] us27 case E: flow `alerts check → join → two integrity checks` with a scripted unhealthy condition. On the dev stack the precondition is "serious alerts > 0", produced by the test by cancelling a running integrity check (then `Monitor.Clear` for the state). Assert that the integrity checks are not started and that the log (if spec 012 is merged) names the failed input. SC-005.

---

## Phase 7: Polish

- [ ] T018 Full regression (backend, unit, e2e); restore rewritten spec 002/007 evidence; counts in `evidence/README.md`; SC-001 timings per type.
- [X] T019 [P] README: *Declared step types* gains the four types, with what each reads and the privilege observed in T001; the contest-area table cites them for *Security/Permissions*, *Web apps/REST*, *Logs/Monitoring* and *Secrets* (FR-013, SC-006).
- [X] T020 [P] `docs/limitations.md`: what `SeriousAlerts` counts (T001); reads are instance-wide (namespace unused); the role cap of 200 accounts; reports are information and never corrective.
- [ ] T021 Clean up `us27-` flows and runs (guarded helper, after the user approves).

## Dependencies

- T001 before T008 and T016 (field names, alert semantics) and before T019 (privileges).
- Phase 2 blocks Phases 3–6. Phases 3, 4 and 5 are independent of each other.
- T017's log assertion needs spec 012; without it, the case asserts only the step states.
- Spec 015 reuses `platform-read` steps in scheduled runs, and spec 014's recording uses the
  security report and the alerts gate.

## Implementation notes (2026-09-29)

- The per-type report tests were grouped: `ReportSystemAlertsTest` (T005) and `ReportSecurityTest`
  (T010, T013, T015: security posture, web application inventory, secrets inventory); the secrecy
  scan (`ResultSecrecyTest`) is `ReadExecutorTest.TestNoSecretInAnyReport`.
- T012's "limited operator gets 403 verbatim" is covered by `ReportSecurityTest.TestUserListRefusedFailsVerbatim`
  (backend) and by spec 011 T001 (c) on a real instance (`sentai-demo` → 403 on security/users);
  `us27` exercises `_SYSTEM` locally and on `iris-target`.
- `/csp/sentai` is reported as `ANONYMOUS_REST_ENDPOINT` (high): its static file server is a REST
  dispatch class. Anonymous by design (spec 010); the README says the finding is expected.

