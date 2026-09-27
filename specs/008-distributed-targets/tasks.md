# Tasks: Distributed Targets (backend)

**Input**: Design documents from `/specs/008-distributed-targets/`. [plan.md](plan.md) is the source
of truth where it conflicts with [spec.md](spec.md) (deviations D-1…D-5). The other documents are
[research.md](research.md) (R-1…R-13), [data-model.md](data-model.md),
[contracts/api-delta.md](contracts/api-delta.md) and [quickstart.md](quickstart.md).

**Tests**: REQUIRED (Constitution: TDD). Every code task writes its failing `%UnitTest` methods
**first**, against `AdminApiDouble` (never a real job), then implements until green.

**Run the suites.** Every code task ends with, in the container:

```objectscript
IRISAPP>do $system.OBJ.LoadDir("/home/irisowner/dev/src","ck-d",,1)
IRISAPP>zpm "test sentai-task -only"
```

and `git status` afterwards (container-side runs must not touch the working tree). Never use
`%UnitTest.Manager.DebugRunTestCase` here. Frontend suites (`cd frontend && npm test && npx
playwright test`) must stay green at T004, T008 and T012 (FR-019, SC-007).

**Test counts**: backend 225 → about 265 methods; frontend unchanged (73 unit, 22 e2e). No test
removed.

**Hard rules for every task**:
- No password, token or refresh token is written to a persistent global, a log, an evidence file
  or a test fixture. Sign-in bodies live in local variables only; run target credentials only in
  `^IRIS.Temp.sentaiTargetCred` (R-5).
- Every call to a target carries the operator's own credential for that target; no service account.
- Refusals and transport errors are kept verbatim; nothing is paraphrased or retried on the
  operator's behalf.
- Local behaviour is unchanged when no step has `target` (FR-019).
- Only catalog step types run remotely; nothing is evaluated or dispatched by a name from input.
- Sequential files: `src/sentai/rest/Dispatcher.cls`, `src/sentai/dispatch/WaveDispatcher.cls` and
  `tests/sentai/unittest/AdminApiDouble.cls` are edited by one task at a time.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (no file in common with an incomplete task).
- **[Story]**: US1 register targets and see their state · US2 run a step on a target and get its
  result · US3 refusals before and during the run.

---

## Phase 1: Setup

- [X] T000 Reflect the plan's deviations in `specs/008-distributed-targets/spec.md` (docs only):
  - add `### Session 2026-09-27 (plan)` under Clarifications pointing to plan §Spec deviations and
    research R-2, R-5, R-8, R-9;
  - **D-1** FR-005 / US1 scenario 4: "categories … as reported; a queue length only when the
    platform provides a read for it (research R-2)";
  - **D-2** FR-009: validation without a credential for a target reports the warning
    `TARGET_NOT_VERIFIED`; dispatch always runs the full checks;
  - **D-3** drop the assumption "the WQM category a step names must exist on the target"; the
    category is checked on the primary;
  - **D-4** add `TARGET_REFUSED` to the Interface codes;
  - **D-5** FR-011: "held only for the run, in non-persistent storage shared by the run's
    processes, erased at its end".
  Commit as docs.

- [X] T001 **Proofs on a real second instance** (plan T0; no product code). Bring up a temporary
  `iris-target` from `intersystems/iris-community:latest-cd` on the compose network (the T002 files
  may be drafted here). From **inside the primary container** (`%Net.HttpRequest` in an IRIS
  session, as the product will call), with a credential for the target:
  1. `POST /api/admin/login` (Basic) → pair and `sub`; `POST /api/admin/refresh`;
  2. `GET /api/admin/info` → `serverVersion`, `namespaces`;
  3. `GET /api/admin/v2/wqm-categories`, and look for a read that returns a **queue length**
     (e.g. `GET /api/admin/v2/wqm-category?name=Default`); record what exists (R-2);
  4. `POST /api/admin/v2/database-dir/integrity-check` `{}` → 202 + `Location`; poll it to
     `Finished`; start another and `POST /api/admin/v2/async-result/cancel?id=` it;
  5. transport error texts: stopped target, unknown host, closed port (R-4, 10 s timeout);
  6. `^IRIS.Temp.x` maps to IRISTEMP on the product image (R-5).
  Save status + body per call, tokens and passwords redacted, to
  `specs/008-distributed-targets/evidence/t0-*.json`, and a `t0-summary.md` stating which R items
  are proven. If (4) fails, stop and report: the feature as planned is not possible.

- [X] T002 [P] Demo environment (FR-020, R-11, R-13):
  - `Dockerfile_target`: `FROM` the same base image, unexpire passwords as the main image does,
    nothing of SentaiTask installed;
  - `docker-compose.yml`: service `iris-target` (not published; reachable as
    `http://iris-target:52773` from `iris`);
  - `iris.script`: `set ^sentai("config","allowInsecureTargets")=1` with a comment that it is for
    the demo network only; create the SSL/TLS client configuration `SentaiTargets`.
  Check: `docker compose up -d --build` brings both up; from `iris`, `GET
  http://iris-target:52773/api/admin/info` answers 401 without a token.

---

## Phase 2: Foundational

- [X] T003 Client endpoint and transport errors (plan D-1, R-4). **Tests first** in
  `tests/sentai/unittest/dispatch/AdminApiClientTargetTest.cls`:
  1. a call with `baseUrl = ""` behaves exactly as today (double keyed by path);
  2. a call with `baseUrl = "http://iris-target:52773"` is routed to the double's entries for that
     base, and records the bearer used per base;
  3. a base scripted as down (`AdminApiDouble.ScriptDown(base, text)`) returns `httpStatus = 0` and
     `transportError = text`;
  4. `Login(base, user, password)` sends Basic auth, returns the pair, and the double records no
     password (only that a login happened).
  Implement in `src/sentai/dispatch/AdminApiClient.cls` (trailing optional `baseUrl`, `ByRef
  transportError`; 10 s timeout and `SentaiTargets` SSL for target calls; `Login`) and
  `tests/sentai/unittest/AdminApiDouble.cls` (key = `baseUrl_urlPath` when a base is given;
  `ScriptDown`). Every existing test stays green unchanged.

**Checkpoint**: nothing user-visible yet; all 225 existing methods green.

---

## Phase 3: User Story 1 — Register targets and see their state (P1) 🎯 MVP

**Independent test**: quickstart (a) and (b).

- [X] T004 [US1] Registry and online flag (FR-001…FR-004, FR-023). **Tests first**:
  - `tests/sentai/unittest/targets/TargetServiceTest.cls`: create/read/list/update/delete; unique
    name (`TARGET_EXISTS`); name pattern and URL rules (`INVALID_TARGET`: path, query, userinfo,
    bad scheme); `INSECURE_TARGET` for `http` non-loopback without the allowance, accepted with it
    and for `127.0.0.1`/`localhost`; online set only through `SetOnline`; the stored object has no
    credential property (reflection over the class definition);
  - `tests/sentai/unittest/targets/TargetRestTest.cls`: every route of contracts §Targets with its
    status codes; any signed-in operator can manage targets.
  Implement `src/sentai/model/Target.cls`, `src/sentai/targets/TargetService.cls`, routes in
  `src/sentai/rest/Dispatcher.cls`. Run the frontend suites once (routes added, nothing else).

- [X] T005 [US1] Sign-in and status (FR-005, FR-006, FR-022, D-1). **Tests first** in
  `TargetServiceTest` / `TargetRestTest`:
  - sign-in returns exactly `{target, accessToken, refreshToken, sub, expiresIn}` from the double;
    a 401 from the target → 401 with its text verbatim and `platformStatus`; down → 502
    `TARGET_UNREACHABLE` + transport text; offline target → 409; after the call, no global under
    `^sentai*` or `^IRIS.Temp.sentai*` contains the password or the tokens;
  - status with `X-Sentai-Target-Authorization`: `reachable`, `version`, `user`, `categories`
    verbatim from the double, `readAt`; down → `reachable:false` + `unreachable.transportError`;
    401 → `refused` with status/detail/platformStatus; missing header → 400; `queueLength` only if
    T001 proved a read for it.
  Implement in `TargetService` and `Dispatcher`.

---

## Phase 4: User Story 3 — Refusals at validation (P1)

- [X] T006 [US3] Step `target`, `remoteCapable`, validation block (FR-007…FR-009, D-2, D-4).
  **Tests first**:
  - `tests/sentai/unittest/model/StepTargetTest.cls`: `target` saved and read back through
    `SaveGraph`/flow read; absent = local;
  - `tests/sentai/unittest/registry/StepTypeTest.cls` (added methods): `IsRemoteCapable` true only
    for `platform-api` types other than `custom`; `/catalog/step-types` carries `remoteCapable`;
  - `tests/sentai/unittest/validation/TargetRuleTest.cls`: in order, `TARGET_NOT_FOUND`,
    `TARGET_OFFLINE`, `STEP_TYPE_NOT_REMOTE_CAPABLE` (each of the in-process types), then with a
    credential: `TARGET_UNREACHABLE` (transport text verbatim), `TARGET_REFUSED` (401 text
    verbatim), `NAMESPACE_NOT_FOUND` from the target's `info.namespaces`, no read-only probe for a
    remote step; without a credential: warning `TARGET_NOT_VERIFIED` only; every finding carries
    `stepId` and `target`; a flow with no `target` produces exactly today's report.
  Implement in `Step.cls`, `Flow.cls` (graph I/O), `StepType.cls`, `FlowValidator.cls` (new
  `TargetFindings`), and `Dispatcher.ValidateFlow` (optional `targetCredentials` body).

---

## Phase 5: User Story 2 — Run a step on a target and get its result (P1)

- [X] T007 [US3][US2] Dispatch with target credentials (FR-010, FR-011, D-5). **Tests first** in
  `tests/sentai/unittest/dispatch/TargetCredentialTest.cls`:
  - a flow using a target without its entry → 400 `TARGET_CREDENTIAL_MISSING` naming target and
    steps; no Run row;
  - redemption refused → the target's status/text verbatim; no Run;
  - redeemed `sub` of another user → 403 `TARGET_CREDENTIAL_USER_MISMATCH` naming both; no Run;
    letter case alone is not a mismatch;
  - success → `^IRIS.Temp.sentaiTargetCred(run, target)` holds the fresh pair; nothing under
    `^sentaiRun` holds it; validation ran with the redeemed token (the double saw it);
  - the loop renews a target pair older than 40 s via the target's refresh; `FinalizeRun` kills
    every `^IRIS.Temp.sentaiTargetCred(run, *)` entry.
  Implement in `Dispatcher.DispatchFlow` and `WaveDispatcher` (store/renew/erase).

- [ ] T008 [US2] Remote execution and results (FR-012…FR-015, FR-018, R-10). **Tests first** in
  `tests/sentai/unittest/dispatch/RemoteStepRunTest.cls`, with one double per base:
  1. a demo-shaped flow (2 local + 1 remote integrity checks into a local 4th): the remote start and
     polls go to the target base with the target token; the local ones to the loopback with the
     local token; `executedOn` = `local`/`iris-target`; `executedAs` = the target `sub` on the
     remote step; states and event versions as for local steps;
  2. `Finished` stores the async-result `result` object (fitted) on local **and** remote steps;
  3. the target's `Error` → `failed` with its `status.summary` verbatim; the join rule unchanged;
  4. editing the target's `baseUrl` mid-run does not change `targetBaseUrl` of a started step;
  5. `/runs/{guid}` returns `executedOn` per step.
  Implement in `StepRun.cls` (`executedOn`, `targetBaseUrl`), `WaveDispatcher` (`StartStep`,
  `ExecuteStepAsync`, `PollInFlightSteps`) and `Dispatcher.ShapeStepRun`. Run the frontend suites
  (run read gains fields; nothing removed).

---

## Phase 6: Control and failure mid-run

- [ ] T009 [US2] Cancel/pause forwarding (FR-017, D-6; closes spec 003 T075 for local steps).
  **Tests first** in `RemoteStepRunTest` and `tests/sentai/unittest/dispatch/` existing control
  tests (added methods): cancelling a running remote step posts `async-result/cancel?id=` to its
  target with the target token, then transitions; a target refusal is recorded verbatim as the
  failure reason; a local running platform step now posts cancel to the loopback; pause of a
  non-pausable type is still 409 with no call.
  Implement in `WaveDispatcher.CancelStep/CancelRun/PauseStep`.

- [ ] T010 [US3] Target down mid-run (FR-016, R-12). **Tests first** in `RemoteStepRunTest`:
  polls answering transport errors keep the step `running` and record the last error; past the
  step's timeout (or 60 min when 0) the step fails with `timed out after N min; last transport
  error: <text>`; sibling steps are untouched; a 4xx stays permanent as today.
  Implement in `WaveDispatcher.PollInFlightSteps` and `SweepTimeouts`.

---

## Phase 7: Polish — acceptance and documentation

- [ ] T011 Quickstart (a)–(f) on the compose stack (T002), saving status + body per call (tokens
  and passwords redacted) to `specs/008-distributed-targets/evidence/quickstart-http-<date>.json`;
  residue check (f); `evidence/README.md` with SC-001…SC-008 results.
- [ ] T012 Docs (FR-021): README section **"Implements DPI-I-588 (Distributed Work Manager)"** with
  the idea's link — implemented (remote dispatch, status and results, target state, online/offline,
  load as the platform reports it), deliberately different (closed catalog, no arbitrary code,
  operator's own credential per target), future (in-process steps on targets, mirror-role
  discovery, callbacks, queue length if the platform exposes it); API table rows for `/targets`;
  `docs/limitations.md` (v1 remote scope = platform-executed types; HTTPS rule and the demo
  allowance). Final full run of backend and frontend suites.

---

## Dependencies & Execution Order

```
T000 (docs) ─ first
T001 (proofs) ─▶ T002 (demo env) ───────────────────────────────┐
T003 (client) ─▶ T004 ─▶ T005 ─┐                                 │
                 T004 ─▶ T006 ─┴─▶ T007 ─▶ T008 ─┬─▶ T009         ├─▶ T011 ─▶ T012
                                                 └─▶ T010 ────────┘
```

- T003 may start before T001 finishes (it only uses the double); T005 and T008 must not be merged
  before T001 proves R-1/R-3 (their contract comes from it).
- Same file, sequential: `Dispatcher.cls` T004 → T005 → T006 → T007 → T008; `WaveDispatcher.cls`
  T007 → T008 → T009 → T010; `AdminApiDouble.cls` T003 only.

## Implementation Strategy

1. **MVP** = T000–T005: targets registered, signed in, status read (US1) — demonstrable with curl.
2. **+ T006–T008**: the demo flow runs with one step on `iris-target` (US2, US3 at validation and
   dispatch) — the core of DPI-I-588.
3. **+ T009, T010**: control and failure mid-run. **Cut first** if time runs short; each becomes a
   documented limitation.
4. **T011, T012**: evidence and README — never cut.
