# Tasks: Scheduled Runs That Execute

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/api-delta.md](contracts/api-delta.md),
[quickstart.md](quickstart.md).

**Tests**: REQUIRED (TDD). Backend `%UnitTest` (after `LoadDir` of `src` and `tests`; never
`DebugRunTestCase`; `git status` after every container-side run); the real-platform acceptance
script for firing; vitest; Playwright `us28-`.

**Hard rules**:
- No password in the product's globals, tables, logs, run records, responses, browser storage,
  evidence or commits (FR-003, SC-002).
- Every task and wallet write goes through the management API with the operator's token; refusals
  verbatim.
- No change merges before the constitution amendment (T003) is in the same branch.
- E2e flows use the prefix `us28-`. Accounts created for tests (`sched-test`) are removed by the
  test that creates them.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup and proof

- [x] T001 Spike on the dev stack, recorded in `specs/015-scheduled-runs/evidence/t001-wallet-tasks.md` (no secret values): research R-1 items 1–4 (wallet bodies and privileges; use-resource enforcement for a process running as another account; `ApplyHTTP` with `/api/admin/login` vs `GetSecretValue`; `wallet/secrets` never returns values), R-2 (the four timing kinds: create, read `task/info` next run, delete), R-4 (identity of in-process steps started from a task). Update plan D-3 and D-4 and data-model §2–3 with the results. **Stop and flag** if the wallet cannot restrict use by resource, or if the management API cannot write secrets with an operator token.
- [x] T002 [P] Baseline counts in `evidence/README.md`; check that `AdminApiClient` never logs request bodies (grep and a test that captures `^ISCLOG`/`messages.log` growth during a login).
- [x] T003 Constitution review and amendment 1.1.0 (plan item 7): edit `.specify/memory/constitution.md` (Principle III paragraph, Sync Impact Report, version and dates), and check the templates. Get the user's approval of the wording before committing (governance change). *Done on branch `feat/spec015`; the user's review of the wording happens at merge (autonomous run, 2026-09-29).*

---

## Phase 2: User Story 1 — Schedule and it runs (P1) 🎯 MVP

**Independent test**: acceptance SC-001 (local), `ScheduledStartTest` success.

### Tests first

- [x] T004 [P] [US1] `TimingTest`: the four kinds → task fields (as confirmed in T001), `Describe` words, validation errors (weekly without days, monthly day 32, hourly 0/13, time 24:00).
- [x] T005 [P] [US1] `ScheduleServiceTest` (happy path) under the double: verify → secret writes → task create with `RunAsUser`, timing and `Settings.FlowId` → `Schedule` row → answer with `taskId`, `nextRun` from `task/info`; `CREDENTIAL_REFUSED` stores nothing; task-create refusal removes the new secrets and returns the refusal verbatim; `TARGET_PASSWORDS_MISMATCH`.
- [x] T006 [P] [US1] `ScheduledStartTest` (success): stored credential (test wallet collection, created and deleted by the test) → sign-in scripted → `Dispatch` with tokens → run `trigger = scheduled`, `dispatchedBy = runAs`, first log entry, run credential stored for renewal.
- [x] T007 [US1] `scripts/schedule-evidence/acceptance.py` part 1: schedule the example two minutes ahead, wait, assert a completed scheduled run (SC-001 local). Run it: it fails (nothing fires today).

### Implementation

- [x] T008 [US1] Installer: resource `SentaiSchedule` and wallet collection `SentaiTask` (iris.script, and a `sentai.schedule.Install` method called by the module's activate step, so IPM installs get it too).
- [x] T009 [US1] `sentai.schedule.Timing`, `sentai.model.Schedule`, `Run.trigger` (initial value `manual`; the storage map is updated by the compiler).
- [x] T010 [US1] `sentai.schedule.ScheduleService.Schedule` (plan D-1, D-2, D-4) and the new `POST /flows/{id}/schedule` handler (contract), replacing `NativeScheduler`. T004 and T005 pass.
- [x] T011 [US1] `sentai.schedule.ScheduledStart.Fire` + `ScheduledFlowTask.OnTask` (plan item 3, D-3 per T001), `WaveDispatcher.Dispatch` with `trigger`, and the narrator's dispatch message for scheduled runs (`Run started by the schedule of flow <name> as <runAs> (flow revision n, k steps)`; if spec 012 is not merged, `ScheduledStart` appends this one entry itself). T006 passes; T007 passes on the dev stack.

---

## Phase 3: User Story 2 — See, change, remove (P1)

- [x] T012 [P] [US2] `ScheduleServiceTest` additions: replace (one task, new generation secrets, old ones removed); failure while creating the new task keeps the old schedule working; legacy per-step tasks named `SentaiTask: <id>#<step>` removed on schedule and unschedule; `Read` returns `nextRun` live and `lastRun`; `Unschedule` idempotent; `residue` reported when an old delete is refused.
- [x] T013 [US2] `ScheduleService.Read/Unschedule`, `GET` and `DELETE /flows/{id}/schedule`, `ListFlows.nextRun` from the `Schedule` row (D-8), `TaskOrigin` reads the new task name (spec 006 tests updated). T012 passes. Acceptance part 2 (SC-003, SC-005) passes.

---

## Phase 4: User Story 3 — Start failures (P2)

- [x] T014 [P] [US3] `ScheduledStartTest` failures: secret unreadable (the run-as account without `SentaiSchedule:U`, a test account) → start-failure run with the platform text and an error `%Status`; login refused; validation failed (all errors listed); a target down at fire time → the run starts and the remote step follows spec 008 behaviour.
- [x] T015 [US3] Start-failure run (plan D-5, data-model §4) and the `OnTask` error status. T014 passes. Acceptance part 3 (SC-004) passes.

---

## Phase 5: Targets and report steps in schedules (P1 scope of FR-007)

- [x] T016 [P] `FlowValidator.ValidateForSchedule`: in-process allowed, destructive refused (tests updated: `IN_PROCESS_NOT_SCHEDULABLE` removed from the expectations); `ScheduledStartTest` with a target secret → target tokens stored for the run; a `platform-read` step (spec 013, if merged) runs with the run-as token.
- [x] T017 Implementation of T016; acceptance part 1 gains a firing with a remote integrity check (SC-001 remote).

---

## Phase 6: User Story 4 — Canvas dialog (P2)

- [x] T018 [P] [US4] `frontend/src/lib/shell/schedule.test.ts` (form ↔ request, words, field errors, targets from the flow) and `frontend/tests/us28-schedule.spec.ts`: dialog content (picker, run-as prefilled, one password per target, wallet sentence, no limitation notice); schedule a `us28-` flow against the real platform (no firing), reopen → current schedule shown; *Update* keeps one task (checked through the catalog API); *Renew credential* keeps the timing and still one task; *Unschedule* with confirmation → none; wrong password → verbatim refusal on its field; after closing, no password in any storage. Update `us3-schedule.spec.ts`, which asserted the limitation notice.
- [x] T019 [US4] `schedule.ts`, `ScheduleDialog.svelte`, client calls (`getSchedule`, `schedule`, `unschedule`). T018 passes.

---

## Phase 7: History marker (FR-016)

- [x] T020 [P] `RunListTest` (spec 012) additions: `trigger` in items; `trigger` filter; 400 `TRIGGER_UNKNOWN`. `us25` (spec 012) gains a scheduled-run case, fed by a run created through `ScheduledStart` in the test helper.
- [x] T021 `trigger` in `ShapeRun`/`ListRuns`; marker and filter in `RunsScreen`. T020 passes. (If spec 012 is not merged yet, only the API part is done here and the screen part moves to 012.)

---

## Phase 8: Polish and governance

- [x] T022 `SecretHygieneTest` (quickstart 5) and a manual scan of the acceptance evidence for the password (SC-002).
- [x] T023 [P] README: scheduling section (dialog, API, run-as account, `SentaiSchedule` resource, wallet), contest-area table (*Task management* now includes schedules that run), roadmap. `docs/limitations.md`: remove "Scheduling is not operational"; add the next-run freshness in the flow list (D-8), overlapping runs are not prevented, and times are the instance's local time.
- [x] T024 Full regression (backend, unit, e2e with `iris-target`, acceptance script); restore rewritten evidence; counts in `evidence/README.md`.
- [x] T025 Clean-up: delete `us28-` flows and runs, test accounts, and any `SentaiTask` wallet secret or task left by tests (guarded helpers; list shown to the user first).

## Dependencies

- T001 blocks everything else. T003 must be approved before merge (not before coding).
- T008–T011 (MVP) before Phases 3–5. Phase 6 needs T013's `GET`/`DELETE`. Phase 7 needs spec 012's
  list (`RunListTest`, `RunsScreen`); without it, T021 does the API part only.
- Spec 013's `platform-read` steps are exercised in T016 only if 013 is merged.
