---

description: "Task list for spike 001-validate-async-job-contract"
---

# Tasks: validate-async-job-contract

**Input**: Design documents from `/specs/001-validate-async-job-contract/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: **None.** This spike carries a Constitution Principle V exemption recorded in [plan.md](plan.md#constitution-check). No automated-test tasks are generated for these units. Human inspection against the acceptance scenarios in [spec.md](spec.md) is the review gate.

**Organization**: Tasks are sliced by *question closed*, not by script structure. Each task's exit criterion is a committed artifact in the working tree. The first task carries the script skeleton, prerequisite check, in-capture-path redaction, evidence layout, and rerun safety — subsequent tasks reuse what it built.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Safe to execute in parallel by a second person (different files, no dependency on incomplete tasks).
- **[Story]**: The user story this task closes (US1..US5 from [spec.md](spec.md)).
- Every task description names the exact artifact path that MUST exist in the working tree when the task is done.

## Phase 1: Setup (Shared Infrastructure)

**Absorbed into T001.** The user directive is that no separate "scaffolding" task exists; the first task that cannot produce its evidence without the script skeleton carries it. That is T001. This phase intentionally contains no tasks.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Absorbed into T001.** Prerequisite check, redaction in the capture path, evidence layout, and rerun safety are all requirements of T001's exit criterion and are established there. No user story can begin without T001; T001 itself is the foundational unit.

---

## Phase 3: User Story 1 — Reachability & authentication (Priority: P1) MVP

**Goal**: A downstream reader can, from the committed evidence alone, reach the management API on IRIS Community, read a captured successful-authentication response field-for-field, and learn how a session is renewed. Closes spec Q1.

**Independent Test**: The reader who did not run the spike opens `evidence/01-login.json` and `evidence/02-refresh.json`, identifies the session-identity fields and the renewal mechanism, and confirms the evidence envelopes conform to [contracts/evidence-envelope.md](contracts/evidence-envelope.md).

**Context this unit needs** (self-contained; do not rely on prior-session memory):
- Read [plan.md](plan.md), [contracts/script-cli.md](contracts/script-cli.md), [contracts/probe-plan.md](contracts/probe-plan.md#1-authenticate) (calls 1–2), [contracts/evidence-envelope.md](contracts/evidence-envelope.md), and [research.md §R4](research.md).
- A running IRIS Community container reachable at `${IRIS_BASE_URL}` (default `http://localhost:52773`).
- `IRIS_USER` and `IRIS_PASSWORD` set in the environment.

- [X] T001 [US1] Produce `evidence/00-info.json`, `evidence/01-login.json` and `evidence/02-refresh.json` by delivering `scripts/validate-async-job-contract/run-spike.sh` (and any sourced helpers under `scripts/validate-async-job-contract/lib/`) that (a) preflights `curl`, `jq`, `IRIS_USER`, `IRIS_PASSWORD`, and `${IRIS_BASE_URL}/api/` reachability per [contracts/script-cli.md](contracts/script-cli.md); (b) archives any pre-existing `specs/001-validate-async-job-contract/evidence/`, along with `compatibility.md` and `decision.md`, into `evidence/.archive/<UTC-timestamp>/` before writing anything new; (c) captures `POST /api/admin/login`, `GET /api/admin/info` (Call 0), and `POST /api/admin/refresh` through a shared capture path that redacts `Authorization` headers, `Set-Cookie`, and credential-shaped body fields per [contracts/evidence-envelope.md](contracts/evidence-envelope.md#what-redaction-targets) *before* any file is written to disk. The `GET /api/admin/info` call MUST be used to extract the platform version and populate `platform.version` on all envelopes; (d) writes each envelope to `specs/001-validate-async-job-contract/evidence/<call_id>.json` matching the schema in [contracts/evidence-envelope.md](contracts/evidence-envelope.md#json-schema-draft-2020-12). Exit criterion: all three files exist, all parse with `jq empty`, neither contains the operator's password or an un-`<REDACTED>` session token, and a rerun archives them along with the compat/decision docs under `.archive/`.

**Checkpoint**: US1 done. The script skeleton, prereq gate, redaction path, evidence layout, and rerun safety are all in place; all subsequent tasks reuse them and only add probe calls.

---

## Phase 4: User Story 2 — Async job contract & decision gate (Priority: P1)

**Goal**: A downstream reader can, from the committed evidence alone, determine whether heavy maintenance operations return an accepted-for-processing response with a job identifier, and whether that identifier drives an observable state / failure reason / timings and supports cancel / pause / resume. Closes spec Q3 and Q4. Together these two answers determine the execution-model decision that T007 records.

**Independent Test**: The reader opens `evidence/06-integrity-check-start.json` and confirms it either carries an accepted-for-processing response with a job identifier or a synchronous completion — either answer closes Q3. Then the reader opens `evidence/07a-*.json`, `07b-*.json`, `07c-*.json`, `08a-*.json`, `08b-*.json`, `08c-*.json` and identifies the state, timing, and transition responses per [contracts/probe-plan.md §7–8](contracts/probe-plan.md#7-observe-the-job).

**Context this unit needs**:
- T001 is complete (script skeleton and capture path exist).
- [contracts/probe-plan.md §6–8](contracts/probe-plan.md#6-start-a-long-running-operation) and [research.md §R6](research.md) (polling interval 1 s, ceiling 120 s).
- The `EXIT` trap must issue `POST /api/admin/v2/async-result/cancel` for any accepted job still outstanding at exit; the trap is written in T002 and reused by T003.

- [X] T002 [US2] Produce `evidence/06-integrity-check-start.json` by extending `scripts/validate-async-job-contract/run-spike.sh` (and helpers under `scripts/validate-async-job-contract/lib/`) to issue `POST /api/admin/v2/database-dir/integrity-check` per [contracts/probe-plan.md §6](contracts/probe-plan.md#6-start-a-long-running-operation), capture the HTTP status code and body through the T001 capture path, and store any returned job identifier in a shell variable. Install an `EXIT` trap that cancels an outstanding job before exit. Exit criterion: the file exists, its `response.status` field is present and captures whatever the platform returned (202 / 200 / other), and after the script exits no job started by this task is left running (verifiable with a follow-up `GET /api/admin/v2/async-result` returning a terminal or cancelled state). Depends on: T001.

- [X] T003 [US2] Produce `evidence/07a-async-result-first.json`, `evidence/07b-async-result-midflight.json`, `evidence/07c-async-result-settled.json`, `evidence/08a-async-result-pause.json`, `evidence/08b-async-result-resume.json`, and `evidence/08c-async-result-cancel.json` by extending `scripts/validate-async-job-contract/run-spike.sh` (and helpers under `scripts/validate-async-job-contract/lib/`) to poll `GET /api/admin/v2/async-result` on a 1 s interval with a 120 s ceiling (both values echoed into each envelope's `notes`), then issue `POST .../pause`, `.../resume`, `.../cancel` in order per [contracts/probe-plan.md §7–8](contracts/probe-plan.md#7-observe-the-job). If a transition returns a "not supported" response, capture that response verbatim and add a `note` naming the transition unsupported (do not skip the file). If call 6's job settles before pause can be issued, start a second integrity-check, capture the substitution as a `note`, and continue. Exit criterion: all six files exist, all parse with `jq empty`, and each records the response as-returned (no synthetic content). Depends on: T002.

**Checkpoint**: US2 done. Q3 and Q4 have committed evidence; the execution-model decision that T007 records is now determinable from the files on disk.

---

## Phase 5: User Story 3 — Response shapes for scheduled tasks (Priority: P2)

**Goal**: A downstream reader can, from the committed evidence alone, read the actual JSON returned when listing scheduled tasks, reading a single task, and reading a task's non-configurable information — including whether identifiers needed by other operations are present. Closes spec Q2.

**Independent Test**: The reader opens `evidence/03-tasks-list.json`, `evidence/04-task-single.json`, and `evidence/05-task-info.json`, and lists every top-level field, its type, and its nesting from those files alone.

**Context this unit needs**:
- T001 is complete.
- [contracts/probe-plan.md §3–5](contracts/probe-plan.md#3-list-scheduled-tasks).
- The task identifier used in calls 4 and 5 is drawn from the first element of whichever array the response to call 3 nests it under; the mechanism is documented in the probe-plan.

- [X] T004 [P] [US3] Produce `evidence/03-tasks-list.json`, `evidence/04-task-single.json`, and `evidence/05-task-info.json` by extending `scripts/validate-async-job-contract/run-spike.sh` (and helpers under `scripts/validate-async-job-contract/lib/`) to issue `GET /api/admin/v2/tasks`, then extract the identifier of the first task from the list response with a `jq` selector matching whatever array the response nests, then issue `GET /api/admin/v2/task?id={id}` and `GET /api/admin/v2/task/info?id={id}` using that identifier. If the list returns zero tasks, add a `note` to `03-tasks-list.json` recording that the instance carries no tasks, write `04-*` and `05-*` as skipped envelopes with `notes: ["skipped — no task available from call 3"]`, and mark this as an open risk for the compatibility statement. Exit criterion: three files exist, all parse with `jq empty`, and each carries an envelope with the platform's actual response body. Depends on: T001.

**Checkpoint**: US3 done. Q2 has committed evidence. T006 (chaining probe) is unblocked.

---

## Phase 6: User Story 4 — Worker-capacity categories (Priority: P3)

**Goal**: A downstream reader can, from the committed evidence alone, confirm that worker-capacity categories are readable, that writing one succeeds, and that a subsequent read reflects the modified value. Closes spec Q5.

**Independent Test**: The reader opens `evidence/09-wqm-categories.json`, `evidence/10a-wqm-category-write.json`, and `evidence/10b-wqm-categories-verify.json`, and confirms the category modified in `10a` shows its new value in `10b`.

**Context this unit needs**:
- T001 is complete.
- [contracts/probe-plan.md §9–10](contracts/probe-plan.md#9-read-worker-capacity-categories).
- The value written must differ from the value read in call 9, so read-back distinguishes "took effect" from "no change". A housekeeping `PUT` restoring the original value is issued after read-back and recorded in `compatibility.md` (not as an evidence file).

- [X] T005 [P] [US4] Produce `evidence/09-wqm-categories.json`, `evidence/10a-wqm-category-write.json`, and `evidence/10b-wqm-categories-verify.json` by extending `scripts/validate-async-job-contract/run-spike.sh` (and helpers under `scripts/validate-async-job-contract/lib/`) to issue `GET /api/admin/v2/wqm-categories`, select one category and record its current value, issue `PUT /api/admin/v2/wqm-category` with a legal value different from the current one, then issue `GET /api/admin/v2/wqm-categories` again. Restore the original value with a final `PUT` and log the restore in a `note` on `10b-*.json`. If the platform returns an error on the write, capture the response verbatim (the file still exists) and add a `note` recording the error; do not attempt a retry. Exit criterion: three files exist, all parse with `jq empty`, and `10b`'s captured body carries the value written in `10a` — or, if it does not, the discrepancy is recorded in the file's `notes` for T007 to escalate as an open risk. Depends on: T001.

**Checkpoint**: US4 done. Q5 has committed evidence.

---

## Phase 7: User Story 5 — Task chaining identifier (Priority: P3)

**Goal**: A downstream reader can, from the committed evidence alone, determine whether any field in `03-tasks-list.json`, `04-task-single.json`, or `05-task-info.json` carries a task's globally unique identifier — the value a dependent task would reference. Closes spec Q6.

**Independent Test**: The reader opens `evidence/11-chaining-probe.json`. If `found: true`, the file names the field, its JSON path in each of the three source files, and one example value. If `found: false`, the file lists every leaf field inspected and the reason each was rejected.

**Context this unit needs**:
- T004 is complete (all three input files present).
- [contracts/probe-plan.md §11](contracts/probe-plan.md#11-chaining-identifier-analysis) and the identifier heuristic in [research.md §R7](research.md).
- This task performs no network call — it is a `jq` analysis over already-captured evidence.

- [X] T006 [US5] Produce `evidence/11-chaining-probe.json` by extending `scripts/validate-async-job-contract/run-spike.sh` (and helpers under `scripts/validate-async-job-contract/lib/`) to run a `jq` analysis over `evidence/03-tasks-list.json`, `evidence/04-task-single.json`, and `evidence/05-task-info.json`. Identify every leaf field whose value is (i) shaped like a globally unique identifier (UUID/GUID or IRIS `%Library.ObjectIdentity`) and (ii) unique to a single task within `03-tasks-list.json`. Write `evidence/11-chaining-probe.json` with either `found: true` and the field name, JSON path per source file, and one redacted example value, or `found: false` with the list of every leaf field inspected and the rejection reason for each. Exit criterion: the file exists, parses with `jq empty`, and matches the "chaining-probe" shape defined in [contracts/probe-plan.md §11](contracts/probe-plan.md#11-chaining-identifier-analysis). Depends on: T004.

**Checkpoint**: US5 done. All six spec questions have committed evidence.

---

## Phase 8: Compatibility statement & execution-model decision

**Purpose**: Convert the captured evidence into the two documents downstream features read directly. This unit produces no new probe calls; it consolidates prior evidence into prose and records the gate decision.

**Independent Test**: A reader who did not run the spike opens `compatibility.md` and can, from that document alone, answer each of Q1–Q6 with an evidence pointer; and opens `decision.md` and finds exactly one of the two decision strings, its rationale citing at least one file under `evidence/06-*` and one under `evidence/07*-*`, and its consequence for scope.

**Context this unit needs**:
- T001–T006 are all complete; every evidence file listed in [research.md §R2](research.md#r2-evidence-layout-on-disk) is present.
- The running IRIS container's version (read from the platform's own reply on any authenticated call) and its image's SHA256 digest (from the container runtime, e.g. `docker inspect --format='{{index .RepoDigests 0}}'`).
- [data-model.md](data-model.md) entities "Compatibility Statement", "Execution-Model Decision", and "Open Risk".

- [X] T007 Produce `specs/001-validate-async-job-contract/compatibility.md` and `specs/001-validate-async-job-contract/decision.md` by extending `scripts/validate-async-job-contract/run-spike.sh` (and helpers under `scripts/validate-async-job-contract/lib/`) to emit both files at the end of a successful run. `compatibility.md` MUST contain the required sections listed in [data-model.md § Compatibility Statement](data-model.md#entity-compatibility-statement) — Environment (version + `sha256:…` digest + base URL + run timestamp), one section per Q1..Q6 with evidence pointers, Deviations from the published contract, Open risks (every question that could not be closed, with the dependent feature it blocks — never silently omitted), and Prior-run archive when an archive was created. `decision.md` MUST name exactly one of `delegate parallel execution to the platform` or `build execution engine inside the product`, cite at least one path under `evidence/06-*` and one under `evidence/07*-*`, and — if the decision is "build inside the product" — record the follow-up action to reduce planned scope so the negative outcome produces a decision rather than a retry. Exit criterion: both files exist at the feature-directory root, `grep -Ec '^## Q[1-6] ' compatibility.md` returns 6, and `decision.md` matches one of the two decision strings verbatim. Depends on: T001, T002, T003, T004, T005, T006.

**Checkpoint**: Spike closes. Every acceptance criterion in [spec.md](spec.md) is verifiable from the committed working tree.

---

## Dependencies & Execution Order

### Task-level dependency graph

```text
T001 ──┬── T002 ── T003 ─────────┐
       ├── T004 ── T006 ─────────┤
       └── T005 ─────────────────┼── T007
                                 │
       (T002 → T003; T004 → T006;
        T005 has no successor
        besides T007)
```

### Phase dependencies

- **Phase 3 (US1 / T001)** is the sole foundational unit. Every later phase depends on it. No user story work may begin before T001 is complete.
- **Phase 4 (US2 / T002 → T003)** is internally sequential (Q3 must produce a job id before Q4 can observe it).
- **Phases 5 (US3), 6 (US4), 7 (US5)** are independent of Phase 4 and of each other, with one exception: Phase 7 (T006) depends on Phase 5 (T004) because Q6 analyses the payloads Q2 captured.
- **Phase 8 (T007)** depends on every other phase.

### User story dependencies

- **US1 (P1)** — no dependencies. MVP scope.
- **US2 (P1)** — depends on US1 (T001).
- **US3 (P2)** — depends on US1 (T001). Independent of US2.
- **US4 (P3)** — depends on US1 (T001). Independent of US2 and US3.
- **US5 (P3)** — depends on US1 and US3 (Q6 reads Q2's evidence).

### Parallel opportunities

After T001 lands, three units are safe to execute in parallel by different people:

- T002 → T003 (US2, sequential internally)
- T004 (US3), then T006 (US5) when T004 lands
- T005 (US4)

`[P]` markers on T004 and T005 record this in the checklist. T002/T003 are not [P]-marked because they are sequential (T003 needs T002's job id). T006 is not [P]-marked because it depends on T004's evidence files. T007 is not [P]-marked because it depends on every prior unit.

## Parallel Example: after T001 lands

Two engineers pick up work concurrently:

```bash
# Engineer A picks up US2 (the decision-gate work):
Task: T002 [US2] — start a long-running operation, capture the accepted response
# then, when T002 is done:
Task: T003 [US2] — poll the job and exercise pause/resume/cancel

# Engineer B picks up US3 first, then US4 (independent branches):
Task: T004 [P] [US3] — capture the three scheduled-task read shapes
Task: T005 [P] [US4] — capture worker-capacity categories, write, and read back
# then, when T004 is done, B (or A, whoever is free):
Task: T006 [US5] — analyse chaining identifier over T004's evidence
```

When A and B both finish their branches, one of them picks up T007 to produce the compatibility statement and the decision.

## Implementation Strategy

### MVP first (US1 only)

1. Complete T001. `evidence/01-login.json` and `evidence/02-refresh.json` exist and are redacted. Q1 has evidence.
2. **STOP and validate**: run the script twice and confirm the second run archives the first under `evidence/.archive/`. Confirm no unredacted secret appears in the working tree (`grep` per [quickstart.md § V3](quickstart.md#v3--no-unredacted-secrets-are-on-disk)).
3. This is the minimum viable spike output: an authenticated, redacted, rerun-safe capture. Everything after this reuses it.

### Incremental delivery

1. T001 lands → validate rerun safety → commit.
2. T002 → T003 land → validate Q3/Q4 evidence → commit. **At this point the decision gate has evidence**; T007 can already be drafted in a scratch buffer.
3. T004 lands → validate Q2 evidence → commit.
4. T005 lands → validate Q5 evidence → commit.
5. T006 lands → validate Q6 evidence → commit.
6. T007 lands → `compatibility.md` and `decision.md` exist → run the six V-scenarios in [quickstart.md](quickstart.md) → commit → spike closes.

### Session isolation

Every task above states its inputs and required context. A task can be picked up in a fresh working session — a fresh checkout, a new operator — by reading this file plus the artifacts named in that task's "Context this unit needs" block. No task requires memory of a previous session.

## Notes

- Every task's exit criterion is an artifact that exists in the working tree; none is defined as work performed.
- Redaction, prereq check, evidence layout, and rerun safety belong to T001 (the first task that cannot produce its evidence without them) — not to a separate scaffolding task, and not to T007.
- No automated tests are generated. Constitution Principle V is exempt for this feature; review is human inspection against [spec.md](spec.md) and the V-scenarios in [quickstart.md](quickstart.md).
- Commit after each task's exit criterion is satisfied. Each commit MUST include both the script changes and the new evidence file(s).
- Never commit files that contain the operator's actual credentials, session tokens, or refresh tokens. If in doubt, run the V3 grep from [quickstart.md](quickstart.md) before committing.
