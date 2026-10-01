# Tasks: Security Inventory — Roles, Resources, Certificates and OAuth (read-only)

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD, as specs 013/015). Backend `%UnitTest` after `LoadDir` of `src` and
`tests` (`zpm "test sentai-task -only"`; never `DebugRunTestCase`; `git status` after every
container-side run); Playwright `us29-`; the real-platform acceptance script for the scheduled case.

**Hard rules**:
- GET only. No report copies a field outside its allow-list (data-model): never `PrivateKeyFile`,
  `PrivateKeyType`, `PrivateKeyPassword`, `ClientSecret` or any key material.
- Certificate validity comes only from the platform's `x509-credential/certificate` answer; the
  product never opens a certificate file (research R-2).
- Refusals are the platform's, verbatim. `ERROR #8864` (`OAuth2NoConfiguration`) is a state, not
  a failure.
- Fixtures (x509 credentials, OAuth objects) are created only on the dev stack, named
  `sentai-e2e-020-*`, from throw-away public certificates (the key file deleted at once, never
  loaded), and deleted in `finally`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [X] T001 Create branch `feat/spec020` from `feat/spec015` and set `.specify/feature.json` to `specs/020-security-inventory`.
- [X] T002 Spike (plan §T001) on the primary and on `iris-target`, recorded in `specs/020-security-inventory/evidence/t001-security-reads.md` (field names and counts only, no secret value): (1) every route of `contracts/api-delta.md` answers as in research R-1; (2) create an OAuth server definition and a client configuration on the dev stack, read them (item field names, the definition id used as `serverId`), delete them; (3) the demo account (`sentai-demo`) answer on each route; (4) whether `sentai.steps.reports.Reader.Get` exposes the status error `id`/`code` of a 404 (plan D-5). Update research R-3/R-4 and data-model §3 field names with the results. **Stop and flag** if client configurations cannot be read per definition (they are then reported "not read" and documented).
- [X] T003 [P] Baseline counts (backend, vitest, e2e) in `specs/020-security-inventory/evidence/README.md`.

---

## Phase 2: Foundational (blocking)

- [X] T004 Tests first in `tests/sentai/unittest/steps/ReportHelpersTest.cls`: `Report.DaysLeft(asOf, notAfter)` (whole days, negative when past, time of day respected for "expired"), `Report.AddIncompleteRead(report, part, text)` (*medium* `INCOMPLETE_READ` with the platform text verbatim), `Report.AddNotAllRead(report, part, omitted)` (*info* `NOT_ALL_READ`, `summary.itemsOmitted` increased), and `summary.asOf` set by `NewReport`.
- [X] T005 Implement those helpers in `src/sentai/steps/reports/Report.cls` (`NewReport` adds `summary.asOf` = `$ZDATETIME($HOROLOG,3)`; existing spec 013 reports keep passing). T004 passes.
- [X] T006 If T002 (4) shows the reader does not expose the error id/code, add `Reader.Get(path, .problem, .errorId)` in `src/sentai/steps/reports/Reader.cls` (id from the platform's `status.errors[0].id`, else ""), with a test in `tests/sentai/unittest/dispatch/ReadExecutorTest.cls`; otherwise record "not needed" in the evidence.

**Checkpoint**: shared helpers ready; spec 013 suites green.

---

## Phase 3: User Story 1 — A scheduled flow warns before a certificate expires (P1) 🎯 MVP

**Goal**: `certificate-expiry-check` lists certificates with days left and fails when any is expired or within `warnDays`.

**Independent test**: with a fixture certificate expiring in 10 days, the step fails with `warnDays` 30 and completes with `warnDays` 5; a scheduled flow with the step produces a failed scheduled run naming the certificate.

### Tests first

- [X] T007 [P] [US1] `tests/sentai/unittest/steps/ReportCertificateExpiryTest.cls` with `AdminApiDouble` scripts: expired → *high* `CERT_EXPIRED` and step error; `daysLeft = warnDays` → *medium* `CERT_EXPIRING`; all valid → completes, statuses `valid`; certificate without `ValidityNotAfter` → *info* `CERT_VALIDITY_UNKNOWN`, not counted; configuration with a certificate file → `CONFIG_VALIDITY_NOT_REPORTED`; configuration without a file → listed, no finding; empty instance → completes with an empty report; configurations list refused but credentials read → `INCOMPLETE_READ`; every read refused → step error with the platform text verbatim; failure reason text `"<n> certificate(s) expired or expiring within <warnDays> days: <alias> (<notAfter>); …"` (first 5); private-key fields present in scripted answers never appear in the report; more than 200 credentials → `NOT_ALL_READ`.
- [X] T008 [P] [US1] Registry assertions in `tests/sentai/unittest/registry/StepTypeTest.cls`: `certificate-expiry-check` present, `executor` `platform-read`, category `security`, available, remote-capable, not destructive, parameter `warnDays` integer 1–365 default 30; catalog size 14. Validation test (existing validator suite, e.g. `tests/sentai/unittest/validation/ParameterSchemaRuleTest.cls`): `warnDays: 0` and `400` → `PARAM_OUT_OF_RANGE`; the type passes `ValidateForSchedule` (not destructive).
- [X] T009 [P] [US1] Fixture helpers (guarded to the dev container and the `sentai-e2e-020-` prefix, as `deleteFlowWithRuns`) in `frontend/tests/iris.ts`: `createTestCertificate(alias, days, container?)` (openssl in the container, key deleted, `%SYS.X509Credentials` load + save) and `deleteTestCertificate(alias, container?)`.
- [X] T010 [US1] `frontend/tests/us29-security-inventory.spec.ts` case A: fixture expiring in 10 days; flow with *Certificate expiry check* (`warnDays` 30) → *Run now* → step failed, Result shows `CERT_EXPIRING` for the fixture first; `warnDays` 5 → completed; fixture deleted in `finally`.
- [X] T011 [US1] `scripts/security-evidence/acceptance.py` (reusing the account/schedule helpers of `scripts/schedule-evidence/acceptance.py`): fixture on the primary, a `us29-accept-*` flow with the check scheduled two minutes ahead as a run-as account, wait for the firing, assert a failed scheduled run whose reason names the fixture; unschedule; delete flow, account and fixture. Run it: it fails until T012–T013.

### Implementation

- [X] T012 [US1] `src/sentai/steps/reports/CertificateExpiry.cls` (extends `Report`): reads `security/x509-credentials`, per credential `security/x509-credential/certificate?alias=` (cap 200), `security/ssl-configurations` and per configuration `security/ssl-configuration?name=` (cap 200); allow-lists and rules of data-model §1; `Build` returns the error status of plan D-3 when `CERT_EXPIRED + CERT_EXPIRING > 0`. T007 passes.
- [X] T013 [US1] Registry entry in `src/sentai/registry/StepType.cls` (contract `api-delta.md`). T008 passes; T010 passes after `publish-canvas.sh`; T011 passes on the dev stack (SC-001).

**Checkpoint**: MVP — the scheduled certificate warning works end to end.

---

## Phase 4: User Story 2 — Who may do what (P1)

**Goal**: `permissions-inventory` lists roles (with resources and granted roles) and resources (public permission) with the fixed findings.

**Independent test**: on the dev instance the report's role and resource counts equal the platform's lists; on `iris-target` it reports that server.

### Tests first

- [X] T014 [P] [US2] `tests/sentai/unittest/steps/ReportPermissionsInventoryTest.cls`: counts from scripted lists; per-role read gives resources and granted roles; `PUBLIC_WRITE_OR_USE_SENSITIVE` for `%DB_*`, `%Admin_*`, `%Development` with `W` or `U`; `PUBLIC_WRITE_OR_USE` for others; `R` alone no finding; `ROLE_GRANTS_ALL` for a role granting `%All` (not for `%All` itself); `failOnFindings` true + *high* → error with the report kept; one role read refused → `INCOMPLETE_READ`; roles list refused and resources read → `INCOMPLETE_READ`; both refused → error verbatim; > 200 roles → `NOT_ALL_READ`.
- [X] T015 [P] [US2] Registry assertions for `permissions-inventory` (parameter `failOnFindings`), catalog size 15, in `tests/sentai/unittest/registry/StepTypeTest.cls`.
- [X] T016 [US2] `frontend/tests/us29-security-inventory.spec.ts` case B: the step locally (counts in the summary equal `GET /api/admin/v2/security/roles` and `…/resources` read by the test) and on `iris-target` (`instance: "iris-target"`).

### Implementation

- [X] T017 [US2] `src/sentai/steps/reports/PermissionsInventory.cls` per data-model §2 and research R-6. T014 passes.
- [X] T018 [US2] Registry entry in `src/sentai/registry/StepType.cls`. T015, T016 pass (SC-002, SC-006).

---

## Phase 5: User Story 3 — OAuth at a glance (P2)

**Goal**: `oauth-inventory` reports the OAuth configuration, or "not configured", and completes.

**Independent test**: on the dev instance (no OAuth) the step completes with `configured: false` and the platform's `ERROR #8864` message.

### Tests first

- [X] T019 [P] [US3] `tests/sentai/unittest/steps/ReportOAuthInventoryTest.cls`: server 404 `OAuth2NoConfiguration` → `configured: false`, `serverMessage` verbatim, no finding, completes; server configured with clients → listed; server definitions → one `client-configurations?serverId=` read per definition (id field from T002); resource servers listed; `OAUTH_PASSWORD_GRANT` and `OAUTH_NON_HTTPS_ADDRESS` (loopback excepted); `ClientSecret` in a scripted answer never appears; any other 4xx on one list → `INCOMPLETE_READ`; every read refused → error verbatim.
- [X] T020 [P] [US3] Registry assertions for `oauth-inventory`, catalog size 16, in `tests/sentai/unittest/registry/StepTypeTest.cls`.
- [X] T021 [US3] `frontend/tests/us29-security-inventory.spec.ts` case C: the step completes on the dev instance; its Result says not configured with the platform's text (SC-003).

### Implementation

- [X] T022 [US3] `src/sentai/steps/reports/OAuthInventory.cls` per data-model §3, research R-3 and plan D-5 (using T006's error id when available). T019 passes.
- [X] T023 [US3] Registry entry in `src/sentai/registry/StepType.cls`. T020, T021 pass.

---

## Phase 6: User Story 4 — The reports read like the others (P2)

**Goal**: palette, inspector, validation and result panel treat the three types as spec 013's reports.

**Independent test**: drag each type, set parameters, validate, run, open results: findings first.

- [X] T024 [P] [US4] `frontend/tests/us29-security-inventory.spec.ts` case D: the three types in the palette's *Security* group; `warnDays` 0 → field error on the inspector after *Validate*; a finished step's Result shows the findings summary before the details. Adjust any existing e2e or vitest assertion that counts step types or palette entries (search `frontend/tests` and `frontend/src` for the spec 013 counts).
- [X] T025 [US4] Only if T024 shows a gap: the smallest change in `frontend/src/lib/run/ResultPanel.svelte` or `frontend/src/lib/flow/document.ts` (for example a date or `daysLeft` column); otherwise record "no frontend change" in the evidence README.

---

## Phase 7: Polish and cross-cutting

- [X] T026 [P] README (`README.md`): *Security inventory* subsection under the report steps (the three types, fixed rules, parameters, the observed `%Admin_Secure` requirement from T002), the scheduled "certificate expires in N days" example (FR-012), contest-area table rows for Security/Permissions and Secrets; step-type table rows.
- [X] T027 [P] `docs/limitations.md`: SSL/TLS configuration files report no validity (register the certificate as an x509 credential to have it checked); OAuth "not configured" state; demo account refused on security reads; caps at 200 items.
- [X] T028 Secrecy (SC-004): scan stored results of the us29 runs, their exports and every file in `specs/020-security-inventory/evidence/` for `PRIVATE KEY`, `PrivateKey`, `ClientSecret`; record the result in the evidence README.
- [X] T029 Full regression (backend, vitest, e2e with `iris-target`, both acceptance scripts of specs 015 and 020); restore rewritten evidence of earlier specs; counts and the acceptance output in `specs/020-security-inventory/evidence/`.
- [X] T030 Clean-up: no `sentai-e2e-020-*` credential, no `us29-` flow, no test account or schedule left on the primary or `iris-target` (list shown in the evidence README); mark tasks; commit on `feat/spec020`; push the branch and open the PR (base `feat/spec015`).

---

## Dependencies

- T001 → T002 (stop condition) → everything else. T003 in parallel with T002.
- Phase 2 (T004–T006) before the user stories. T006 only blocks US3.
- US1 (T007–T013) is the MVP and needs spec 015 for T011. US2 and US3 are independent of US1 and of
  each other (each adds its own class and entry; the registry size assertions are cumulative — if
  stories run out of order, assert the size once in T029 instead).
- US4 after at least one of US1–US3. Polish last.

## Parallel examples

- After T005: T007, T008, T009 together (different files); T014–T015 and T019–T020 can start in
  parallel with US1's implementation.
- In Polish: T026 and T027 together.

## Implementation strategy

1. MVP = Phases 1–3: the certificate check with the scheduled acceptance — the story the review
   singled out for the jury.
2. Add US2 (permissions), then US3 (OAuth), each shippable on its own.
3. US4 and Polish close the feature; push and open the PR.
