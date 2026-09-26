# Feature Specification: Backend Hardening — Reduce to Proven Truth

**Feature Branch**: `004-backend-hardening`

**Created**: 2026-09-23

**Status**: Implemented (v1; refined 2026-09-23)

**Input**: Escalations E-1, E-2, E-3 and findings F-1, F-3, F-4 from the spec 003 real-instance
verification ([quickstart-evidence.md](../003-backend-objectscript/quickstart-evidence.md),
[HANDOFF.md](../003-backend-objectscript/HANDOFF.md)), validated platform contracts from
[spec 001 compatibility.md](../001-validate-async-job-contract/compatibility.md).

## Clarifications

### Session 2026-09-23

- Q: New flows default to `SENTAI.DEFAULT`, which does not exist on the target instance — change
  the default to the built-in `Default`? → A: No. Keep `SENTAI.DEFAULT`; the "no flow schema
  change" constraint wins. Validation reports `CATEGORY_NOT_FOUND` and the operator picks an
  existing category. The quickstart and README say so.

### Session 2026-09-23 (minimum shippable scope)

- Q: Should `defragment-globals` stay in the v1 support set? → A: No. Its endpoint exists (405 on
  GET) but a start was never observed end to end. For the deadline the support set is
  **`integrity-check` only**; `defragment-globals` is `available: false` until proven in a future
  spec. D-1 amended accordingly (supersedes the earlier "supported, best-effort" wording).
- Q: What is the minimum acceptance path the 004 quickstart must prove? → A: Keep only:
  (1) create a flow of 2–3 `integrity-check` steps in fan-out/fan-in with an existing category,
  validate → `errors: []`, dispatch → 202, track via SSE to `completed`; (2) a flow with an
  unsupported type is refused at validate/dispatch with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`;
  (3) a flow naming a non-existent category is refused with `CATEGORY_NOT_FOUND`. Demoted to
  evidence/notes (not in the main quickstart): scheduling, runs longer than 60 s / 401 behavior,
  real WQM write (covered by unit test + one recorded manual write), defragment probe, destructive
  schedule refusal, sanitation.
- Q: Scheduling status in 004? → A: Present for contract continuity, explicitly non-operational,
  not part of the acceptance path. Wording: *"`/schedule` validates the flow and registers a
  native task, but scheduled runs cannot authenticate to the platform in v1 and are not a
  supported execution path. Use manual dispatch."*
- Q: Keep User Story 3 as a full story? → A: No. Downgraded to a cross-cutting documentation
  requirement (FR-007). Smallest deliverable: a "Known limitations (v1)" README section plus
  spec 003 HANDOFF entries E-1/E-2/E-3 marked "addressed by 004".

## Context and Problem

Spec 003 delivered a functionally complete backend (86/86 tests on IRIS 2026.2). Real-instance
verification (T070) proved the **code is correct** but **the platform does not support everything
the product promises**:

| Promise the product makes today | What T070 proved | Ref |
|---|---|---|
| 7 executable step types | Only `integrity-check` proven end to end; `defragment-globals` endpoint exists (405 on GET) but start never observed; the other 5 return 404 | E-2 |
| Steps are driven for the whole run | The run's platform credential expires 60 s after dispatch; later calls return 401 | E-1 |
| Flows can be scheduled | Scheduled runs are created and keep wave order, but carry no credential; every platform call returns 401 | E-3 |
| WQM categories can be edited | The write targets an endpoint that is not the validated contract; no real write can succeed | F-1 |
| Built-in categories are valid | The nesting invariant rejects every built-in category (`MaxTotalWorkers = 0`) | F-4 |
| An invalid category is caught at validation | It is only caught at enqueue, as a step failure | F-3 |
| A step's `databaseDirectory` targets the operation | The platform start request carries no parameters; the platform chooses what to check | E-2 |

A demo that touches any of these breaks visibly. This spec **adds no features**: it blocks what
was not proven, fixes the two contracts that contradict evidence, and documents the rest as
known limitations.

## Objective

After this spec, an operator who composes, validates, dispatches and tracks a flow — and whose
flow validates clean — never hits a platform 404, an invariant violation on built-in data, or an
unknown-category failure at enqueue. Every remaining failure mode (60 s credential, scheduled
runs, unforwarded parameters) is written down where the operator reads it before they hit it.

## Scope

### In scope

1. Declare the v1 support set of step types (D-1) and expose it through the existing step-type
   catalog.
2. Block unsupported step types on every execution path: validate, dispatch, schedule and rerun.
3. Fix the WQM category write to the validated contract (F-1).
4. Treat `0` as unbounded in the nesting invariant (D-3, F-4).
5. Reject unknown WQM categories at validation (F-3).
6. Document scheduling as non-operational (D-2), plus E-1 and the other limitations, in the
   README and quickstart; mark E-1/E-2/E-3 as addressed-by-documentation in the spec 003 handoff.
7. Reduce the quickstart to the minimum acceptance path (see Clarifications) using only
   `integrity-check`.

### Out of scope

- Credential refresh or a server-side identity for background/scheduled runs (E-1, E-3).
- Propagating cancel to the platform job (F-2).
- Cleaning historical `running` runs (F-5) — handled by the sanitation script.
- Forwarding step parameters (`databaseDirectory`, `daysToKeep`, …) to the platform.
- Proving `defragment-globals` — it stays unavailable in v1 (D-1).
- Demonstrating scheduling as a success path (D-2).
- Removing any type, endpoint, class or test fixture — including `/schedule`, typed confirmation
  and pause, which remain implemented even though no supported type exercises them (see
  Consequences of D-1).
- New step types, new endpoints, new error payload shapes, or frontend work beyond what the
  palette gets for free from the catalog.
- Reopening any spec 003 decision (join policy, scheduler, GUID, isDestructive derivation,
  single instance, pause restriction, destructive-not-schedulable).

## Decisions (closed — do not reopen)

### D-1: v1 step type support set = `integrity-check` only *(amended 2026-09-23)*

| Type | Platform probe (T070) | v1 |
|---|---|---|
| `integrity-check` | proven end to end (202 → Running → Finished) | **Supported** |
| `defragment-globals` | endpoint exists (405 on GET); start not observed | Unsupported (until proven) |
| `compact-globals` | 404 | Unsupported |
| `switch-journal` | 404 | Unsupported |
| `purge-audit-records` | 404 | Unsupported |
| `purge-task-history` | 404 | Unsupported |
| `custom` | 404 (`task/custom`) | Unsupported |

All 7 types stay in the catalog so saved flows remain loadable; unsupported types are marked
unavailable and blocked on execution paths.

**Consequences of D-1** (accepted, documented, not fixed):
- The supported type is neither destructive nor pausable. Typed confirmation, the
  destructive-not-schedulable rule and step pause remain implemented and tested, but no flow that
  validates clean in v1 can reach them; pause on any v1 step returns 409.
- The spec 003 canonical flow (step 04 `purge-audit-records`) no longer validates.

### D-2: scheduling is non-operational in v1

`POST /flows/{flowId}/schedule` keeps working at the API level (validation gate, native task
creation) for contract continuity. Fire-time runs fail with 401 because they carry no credential
(E-3). No code change: the 401 recorded verbatim as the step's failure reason is the honest
observable behavior. Scheduling is **not** part of the acceptance path. Documented wording:

> `/schedule` validates the flow and registers a native task, but scheduled runs cannot
> authenticate to the platform in v1 and are not a supported execution path. Use manual dispatch.

### D-3: `0` means unbounded

`MaxWorkers = 0` or `MaxTotalWorkers = 0` means "no limit" and compares as +∞ in the invariant
`defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`. Only these two fields get
this treatment.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Unsupported step types are caught before anything runs (Priority: P1)

An operator opens a flow (new, or saved before this spec) that contains types the platform cannot
execute. Instead of discovering a 404 mid-run, they see — at validation — exactly which steps are
unsupported and why, and nothing is dispatched or scheduled until they are removed.

**Why this priority**: E-2 is the most visible false promise; 5 of 7 palette entries fail at run
time today.

**Independent Test**: Create a flow with one supported and one unsupported step; validate,
dispatch and schedule it; confirm each is refused naming only the unsupported step, and that the
step-type catalog reports availability per type.

**Acceptance Scenarios**:

1. **Given** a flow whose only step is `compact-globals`, **When** the operator validates it,
   **Then** the response is the existing validation-failure response with one error
   `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` naming that step id and type.
2. **Given** the same flow, **When** the operator dispatches it, **Then** dispatch is refused with
   the same error and no run is created.
3. **Given** the same flow, **When** the operator schedules it, **Then** scheduling is refused
   with the same error and no native task is created.
4. **Given** a flow with `integrity-check` (01) and `purge-audit-records` (02), **When**
   validated, **Then** only step 02 has an availability error; **When** step 02 is removed and
   the flow re-validated, **Then** `errors: []`; **When** dispatched, **Then** 202 and step 01
   runs to `completed` on the real platform.
5. **Given** the step-type catalog, **When** the operator (or the palette) reads it, **Then** it
   lists all 7 types, `integrity-check` with `available: true`, the other 6 with
   `available: false`.
6. **Given** a saved flow referencing an unsupported type, **When** the operator reads it,
   **Then** it loads unchanged (no save-time rejection).

---

### User Story 2 — Built-in and real WQM categories work end to end (Priority: P1)

An operator reads the platform's built-in categories, uses them in flows, and edits a category
through the product — and each call behaves as the platform does, with no false invariant
violations and no writes that can never succeed.

**Why this priority**: F-1 and F-4 make the WQM screen unusable against a real instance; F-3
turns a typo into a run-time failure.

**Independent Test**: Against the real instance, read `Default`, write a valid update to a
category and read it back, and validate a flow that names a non-existent category.

**Acceptance Scenarios**:

1. **Given** the built-in `Default` category reporting `MaxTotalWorkers = 0`, **When** the
   operator reads it or references it in a flow, **Then** no invariant violation is reported.
2. **Given** a valid category update, **When** the operator writes it, **Then** it is sent using
   the validated platform write contract (spec 001 evidence 10a), returns success, and the change
   is visible on the next read.
3. **Given** an update that violates the invariant with non-zero values (e.g. `maxWorkers = 2`,
   `maxTotalWorkers = 1`), **When** written, **Then** it is still refused with 422 before any
   platform call.
4. **Given** a flow whose step names `wqmCategory: "NONEXISTENT"`, **When** validated, **Then**
   one error `CATEGORY_NOT_FOUND` names the step id and the category, and dispatch/schedule are
   refused with the same error.
5. **Given** a flow whose steps name no category and whose flow-level default category does not
   exist on the instance, **When** validated, **Then** `CATEGORY_NOT_FOUND` is reported for the
   flow-level default. The product default for new flows stays `SENTAI.DEFAULT` (no flow schema
   change — see Clarifications): an operator who does not set a category sees this error at
   validation and must pick an existing one (e.g. `Default`).

---

*User Story 3 (documentation) was downgraded to the cross-cutting requirement FR-007 — see
Clarifications.*

### Edge Cases

- **Mixed errors**: an unsupported step also failing another rule (e.g. `custom` without a class,
  `purge-audit-records` without `daysToKeep`) reports all applicable errors; the availability
  error is additive, never suppresses or replaces existing ones.
- **Unsupported + destructive on schedule**: `purge-audit-records` on `/schedule` reports both
  `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` and `DESTRUCTIVE_NOT_SCHEDULABLE`.
- **Confirmation vs availability on dispatch**: a flow with an unsupported destructive step is
  refused for availability (validation failure) — the operator is never asked to type a
  confirmation for a step that cannot run.
- **Rerun of a historical step**: rerunning a step of an unsupported type in a run created before
  this spec is refused with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`; nothing is sent to the platform.
- **Unknown type string**: a type outside the catalog keeps reporting `UNKNOWN_STEP_TYPE` only
  (not also the availability error).
- **Both limits zero**: `maxWorkers = 0` and `maxTotalWorkers = 0` → ∞ ≤ ∞ holds.
- **Zero in other fields**: `defaultWorkers = 0` or `maxActiveWorkers = 0` are ordinary numbers
  (0 ≤ anything holds); they are not "unbounded".
- **"Dynamic (N)" values**: already normalized to N before the invariant is evaluated; unchanged.
- **Category lookup cannot be performed** on an operator-initiated path (validate, dispatch,
  schedule): validation reports `CATEGORY_NOT_FOUND` (fail closed) rather than passing a category
  it could not confirm.
- **Scheduled fire time** (no credential by design, D-2/E-3): the category rule is skipped, so a
  scheduled run is still created and its steps fail with the verbatim 401 exactly as D-2
  documents. Categories were already checked when the schedule was created.
- **Tasks scheduled before this spec** containing now-unsupported types: not revalidated at fire
  time; they already fail with 401 under D-2. No migration.
- **Run exceeding 60 s**: steps whose platform calls happen after the credential expires fail
  with the platform's 401 preserved verbatim as the failure reason — documented, not fixed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001 — Availability in the catalog.** Each step type in the catalog carries an `available`
  boolean: `true` for `integrity-check`, `false` for the other 6. The
  existing `GET /catalog/step-types` response includes the field. Availability is declared in one
  place and read by every rule below.
- **FR-002 — Availability blocks execution.** Validation emits `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`
  (naming step id and type) for every step whose type is in the catalog and unavailable. Because
  dispatch and schedule are gated by validation, both are refused. Rerun of a step whose type is
  unavailable is refused with the same code before any platform call.
- **FR-003 — Documents stay loadable.** Creating, reading and saving a flow with unavailable types
  is unaffected; the flow document schema does not change.
- **FR-004 — WQM write contract.** A category write uses the validated platform contract (spec 001
  evidence 10a: update-by-name with the name as a query parameter). The existing test double must
  reject the old, unvalidated path so the regression cannot return.
- **FR-005 — Zero is unbounded.** Every evaluation of the nesting invariant (category read, write,
  flow validation) treats `0` in `maxWorkers` or `maxTotalWorkers` as +∞, and no other field.
- **FR-006 — Category existence.** Validation emits `CATEGORY_NOT_FOUND` (naming step id and
  category) when a step's effective category — its own `wqmCategory`, else the flow's default
  category — does not exist on the target instance at validation time. Each missing category is
  reported per step that resolves to it.
- **FR-007 — Documentation (cross-cutting, replaces former US-3).** README gains a "Known
  limitations (v1)" section stating: only `integrity-check` runs in v1; scheduled runs fail with
  401 (D-2 wording); platform calls more than 60 s after dispatch fail with 401; step parameters
  are not forwarded; flows must name an existing WQM category. The runnable quickstart contains
  only the minimum acceptance path (Clarifications); demoted items go to an evidence/notes
  section. Spec 003 HANDOFF marks E-1/E-2/E-3 "addressed by 004" and F-1/F-3/F-4 fixed.
- **FR-008 — No regressions.** All existing tests pass, adjusted only where they encoded a
  now-false promise (e.g. a canonical fixture using an unsupported type, a test double accepting
  the old write path). No test is deleted to make the suite pass.

### Key Entities

- **Step type (catalog entry)**: gains `available`. Existing `destructive`/`pausable` unchanged.
- **Validation error codes**: two new codes, `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` and
  `CATEGORY_NOT_FOUND`, in the existing `{stepId, code, message}` error shape.
- **WQM category**: invariant semantics change for zero only; shape unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 of 6 unsupported types can reach the platform through validate, dispatch,
  schedule or rerun (each path tested per type: 24 refusals, 0 platform calls).
- **SC-002**: A flow composed only of supported types with an existing category validates with
  `errors: []` and runs to `completed` on the real instance with no 404 in any step's failure
  reason.
- **SC-003**: 3 of 3 built-in categories (`Default`, `SQL`, `Utility`) read without an invariant
  violation; 1 real category write succeeds and is confirmed on read-back.
- **SC-004**: A flow naming a non-existent category is refused at validation — 0 runs created, 0
  enqueue-time category failures.
- **SC-005**: The updated quickstart executes end to end on the real instance with 0 steps whose
  observed result contradicts the expected column.
- **SC-006**: 100% of the pre-existing test suite passes, plus new tests for each FR-001…FR-006.
- **SC-007**: Delivered within ~8 tasks / ~3 hours; no new endpoint, class of capability, or
  schema change.

## Assumptions

- Category existence is confirmed by reading the platform's category list with the operator's
  own credential at request time (the platform stays the source of truth, Constitution III), not
  from a local copy.
- "Available" is a static, per-release declaration from T070 evidence, not a runtime probe; it
  changes only by editing the catalog in a future spec.
- The frontend palette reads the catalog endpoint; any greying-out of unavailable types is a
  frontend concern and out of scope here.
- Test count baseline: 86 (quickstart-evidence.md, 2026-09-23).

## Dependencies

- Spec 003 backend as implemented (86/86 on IRIS 2026.2).
- Spec 001 evidence 09/10a/10b (WQM read/write contracts).
- Real IRIS 2026.2 dev instance for SC-001…SC-005.
