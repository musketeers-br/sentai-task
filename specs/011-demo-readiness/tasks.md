# Tasks: Demo Readiness — A Public Demo That Stays Up and a README That Sells in One Screen

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [quickstart.md](quickstart.md). No `contracts/`: the product API
does not change.

**Tests**: REQUIRED (TDD, Constitution V). In every phase the test is written first and seen
failing for the reason the story fixes. Backend: IRIS `%UnitTest` (`zpm "test sentai-task -only"`
after `LoadDir` of `src` **and** `tests`; check `git status` after every container-side run).
Frontend: vitest and Playwright against the dev stack. Demo stack: `scripts/demo/acceptance.sh`
against an isolated compose project (quickstart A).

**Hard rules**:
- The privileged secret never appears in the repository, in a command line (stdin only), in logs
  or in evidence.
- The product never clears the alert state by itself (FR-020). Only `reset.sh` does.
- The default `docker compose up` stack is unchanged (`git diff docker-compose.yml` is empty).
- E2e flows use the prefixes `us22-` and `us23-`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [ ] T001 Spike on an isolated compose project (not the dev stack), recorded in `specs/011-demo-readiness/evidence/t001-demo-role.md`:
  - (a) secure the privileged accounts with the rule of research R-2 and prove `_SYSTEM:SYS` → 401 on both instances, the canvas still loads, and `iris session` still works from the host;
  - (b) find the least-privilege resource set of role `SentaiDemo` by running the example and showcase flows as `sentai-demo` (R-4), adding one resource per verbatim refusal;
  - (c) prove `GET /api/admin/v2/security/users` → 403 and `purge-task-history` refused for that account;
  - (d) `docker compose restart` keeps (a) and (b) (R-5).
  If (b) needs `%Admin_Secure` or `%All`, **stop and flag it**.
- [ ] T002 [P] Create `specs/011-demo-readiness/evidence/README.md` listing the evidence files and the baseline counts (backend 269, unit 145, e2e 65 with `iris-target` up). Run the baseline and record it.

---

## Phase 2: User Story 5 — Cancel alert notice (P2, but first: smallest and on every installation)

**Independent test**: us22 — notice present when a platform job runs, absent for in-process only.

- [ ] T003 [P] [US5] Write `frontend/src/lib/run/cancel-alert.test.ts`: running local integrity check → true; running remote integrity check → true; queued integrity check → false; running `db-size-report` → false; unknown type → false; `stepCancelRaisesAlert` per step. See it fail (no module).
- [ ] T004 [P] [US5] Write `frontend/tests/us22-cancel-alert-notice.spec.ts`: (1) flow `us22-ic` with one integrity check on USER, *Run now*, wait for `running`, open *Cancel wave* → `cancel-alert-notice` visible with a link to `docs/limitations.md`; choose *Keep running*; (2) click the step's *Cancel* → a confirmation with the notice; *Keep running* → still running; then cancel the run through the API and clear the alert (`Monitor.Clear` via `tests/iris.ts`); (3) the spec 010 example, *Run now*, *Cancel wave* before it ends → no notice; (4) the step *Cancel* tooltip equals the D-19 text. See it fail.
- [ ] T005 [US5] Implement `frontend/src/lib/run/cancel-alert.ts` (plan D-17). T003 passes.
- [ ] T006 [US5] `RunScreen.svelte`: notice paragraph in *Cancel wave?* when `cancelRaisesAlert`; `RunNode.svelte`: confirmation dialog for such steps, one-click cancel otherwise, tooltip text D-19. Gate: `npm test && npm run check && npm run build && bash ../scripts/publish-canvas.sh && npx playwright test us22 us4`. T004 passes; us4 unchanged.

**Checkpoint**: US5 shippable on its own.

---

## Phase 3: User Story 3 (part 1) — Seed the example and the showcase

**Independent test**: `DemoTest` seed cases.

- [ ] T007 [P] [US3] Create the fixture `tests/sentai/unittest/fixtures/example-flow.json` from `exampleDefinition()` and add a case to `frontend/src/lib/flows/example.test.ts` that compares both (R-6). It passes now (the fixture is taken from the code), and it must fail if either changes.
- [ ] T008 [US3] Write `tests/sentai/unittest/DemoTest.cls`: `TestSetupRefusesOnDevWithoutFlag` (Setup without the `force` argument on an instance without the marker writes nothing and returns ok=false); `TestSeedCreatesShowcase` (steps, edges and join exactly as data-model §5; `FlowValidator.Validate` gives 0 errors with a registered target double); `TestSeedIsIdempotent` (a second Seed changes neither id nor revision); `TestSeedRepairsChangedShowcase` (after deleting step 04, Seed restores it); `TestExampleMatchesFixture`. Every test removes what it creates (SentaiTestCase). See them fail.
- [ ] T009 [US3] Implement `src/sentai/demo/Demo.cls`: `Setup(force)`, `Seed()`, `ExampleDefinition()`, `ShowcaseDefinition()`, returning the outcome value of data-model §4. T008 passes; full backend suite green.

---

## Phase 4: User Story 4 — Reset and status

**Independent test**: `DemoTest` reset/status cases; `acceptance.sh` item 7.

- [ ] T010 [US4] Add to `DemoTest`: `TestResetRefusesWithoutMarker`; `TestResetLeavesSettingsAlone` (the `^sentai("config")` keys other than the marker, and the target's address, are unchanged — FR-012); `TestResetRemovesVisitorFlows` (two visitor flows with runs, step runs and log entries → gone; seeded flows kept with their runs); `TestResetRecordsLastReset`; `TestStatusShape` (fields and counts of data-model §4). See them fail.
- [ ] T011 [US4] Implement `Demo.Reset()` and `Demo.Status()` (plan D-14, D-15). T010 passes.
- [ ] T012 [US4] Write `scripts/demo/reset.sh` and `scripts/demo/status.sh` (`--env-file`, `COMPOSE_PROJECT_NAME`, `flock`, `Monitor.Clear` and demo password restore on both instances through `demo-account.script`, exit codes), and write `scripts/demo/acceptance.sh` item 7 first, seen failing.

---

## Phase 5: User Story 2 — The public demo stack

**Independent test**: `acceptance.sh` items 1–6 and 8.

- [ ] T013 [US2] Write `acceptance.sh` items 1–6 and 8 (quickstart A). Run against nothing → fails.
- [ ] T014 [P] [US2] `scripts/demo/secure-accounts.script` and `scripts/demo/demo-account.script` (ObjectScript for `iris session … -U %SYS`, secret on stdin, rule R-2, role from T001).
- [ ] T015 [P] [US2] `docker-compose.demo.yml` (plan D-5) and `demo/Caddyfile` (D-6).
- [ ] T016 [US2] `scripts/demo/up.sh` in the order of plan D-9, writing `demo.json` (data-model §2) into `/opt/sentai-web` and calling `Demo.Setup(1)`. Run `acceptance.sh` on an isolated project: all items pass. Record the output (secret redacted) in `evidence/t016-acceptance.txt`.

**Checkpoint**: the demo can be deployed.

---

## Phase 6: User Story 3 (part 2) — Sign-in hint

- [ ] T017 [P] [US3] Write `frontend/src/lib/shell/demo-info.test.ts` (valid, missing field, wrong types, oversize, non-JSON → null) and `frontend/tests/us23-demo-sign-in-hint.spec.ts` (route `**/demo.json` fulfilled → hint with account and showcase name; 404 → no hint). See them fail.
- [ ] T018 [US3] Implement `demo-info.ts` and the hint in `SignIn.svelte` (plan D-13). T017 passes; the full e2e suite stays green.

---

## Phase 7: User Story 1 — README first screen

- [ ] T019 [US1] Add `acceptance.sh --readme`: checks the heading order of FR-001 and that every relative link in the *Try it* block and the area table resolves to a file or anchor. See it fail on today's README.
- [ ] T020 [US1] Copy the picture to `assets/sentai-run.png` (plan D-4) and restructure `README.md` (D-1, D-2, D-3), add the "Public demo" section (up, reset, status, cron, "never `down`, use `restart`"), and update the roadmap (010 done; 011–015 named). T019 passes.
- [ ] T021 [US1] After the VM is up (team action, outside the repo), replace the demo address placeholder with the real one and update the Open Exchange demo link (team action; confirm with the user before any outward-facing change).

---

## Phase 8: Polish

- [ ] T022 Full regression: backend, unit, e2e (with `iris-target` up), `acceptance.sh`. Restore any spec 002/007 evidence the e2e run rewrote. Record the counts in `evidence/README.md`.
- [ ] T023 [P] `docs/limitations.md`: add a stable anchor to the cancel-alert item (used by the notice link) and a "Public demo" note (the demo account sees verbatim refusals by design; categories are not restored by the reset).
- [ ] T024 Deploy on the VM (team), run `status.sh` there, and record SC-002 (time to up) and SC-004 (visitor to showcase finished) in `evidence/README.md`.

## Dependencies

- T001 blocks T014 and T016 (the role content and the securing rule).
- T009 blocks T011; T011 blocks T012 and T016.
- T016 blocks T021 and T024. T020 can merge before the VM exists (the placeholder is replaced in T021).
- Phases 2 (US5) and 6 (US3 hint) are independent of the demo stack and can run in parallel with Phases 3–5.
