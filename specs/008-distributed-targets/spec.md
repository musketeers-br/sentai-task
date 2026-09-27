# Feature Specification: Distributed Targets (backend)

**Feature Branch**: `008-distributed-targets`

**Created**: 2026-09-27

**Status**: Draft

**Input**: Implement InterSystems Ideas **DPI-I-588 "Distributed Work Manager"**
(<https://ideas.intersystems.com/ideas/DPI-I-588>, status *Community Opportunity*) within
SentaiTask's existing model: a flow step can run on another reachable instance of the platform
(a **target server**), and the run tracks its state and collects its result exactly as it does for
local steps. Backend only; the canvas screens are spec 009.

## Context and Problem

The idea asks for work dispatched in the background to any reachable server of the platform (for
example an async or failover mirror member), with status and progress checks, result collection,
and management of each target (online/offline, load through queue length). The use case: free the
primary by running resource-heavy maintenance elsewhere, with full control and the results back on
the primary.

SentaiTask already does the local half:

| Need in the idea | What SentaiTask does today | Gap |
|---|---|---|
| Dispatch work in the background | Each step is queued on a Work Queue Manager category and followed to a terminal state with its own identifier | Only on the instance SentaiTask runs on |
| Check status/progress | Run read and live events per step (`queued` → `running` → terminal) | Local only |
| Collect results | The step's `result` is kept on the run | Local only |
| Platform-executed work | `integrity-check` and the other platform-api types go through the platform's management API | The management API address is fixed to the local instance |
| Manage targets (online/offline, load) | — | Nothing |

Because platform-executed steps are already calls to the platform's management API, running one
on another instance means making **the same calls against that instance's management API**, with
the operator's own credential for it.

## Clarifications

### Session 2026-09-27

- Q: How does the operator obtain a credential for a target (for its status read and for
  dispatch)? → **Through the primary (A).** A product call signs the operator in to the target:
  it forwards their user name and password to that target's sign-in once and returns the
  target's credential pair to the caller. The primary keeps nothing; the password crosses it in
  transit only. No configuration is needed on the targets, and the same call serves the API and
  the canvas (FR-022).
- Q: Who may register, edit, delete a target and set it online/offline? → **Any signed-in
  operator (A)**, as for flows. A wrong or hostile address only ever receives calls made with the
  operator's own credential for it, which the operator typed for that target (FR-023).

## Scope

**In scope (v1)**:

- A registry of target servers kept by the product (no credential stored).
- A status read per target, made against the target with the operator's credential for it.
- An optional `target` on a step; validation and dispatch of **platform-executed** step types on a
  target; tracking, failure reasons and results as for local steps; `executedOn` on each step run.
- A second platform instance in the reproducible demo environment.
- A README section stating what of DPI-I-588 is implemented, what is deliberately different and
  what is future.

**Out of scope**:

- Automatic target discovery from mirror configuration; mirror-role awareness.
- Callbacks from the target to the primary.
- Load-based automatic placement (the operator places each step).
- Declared in-process step types on a target (they need SentaiTask installed there).
- Scheduling a flow whose steps use a target (scheduling is already non-operational in v1).
- Any canvas change (spec 009).

**Deliberate difference from the idea (Constitution II)**: the idea mentions calling arbitrary
methods and functions remotely. SentaiTask does **not** do that. Only step types from the product's
declared catalog run on a target, and no code, method name or class name is ever taken from input.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Register targets and see their state (Priority: P1) 🎯 MVP

An operator registers the other instances they want to use as targets: a unique name, a base
address (scheme, host, port) and an optional description. They list, read, edit and delete targets.
For any target they ask for its status and get, as the target itself reported it: whether it is
reachable, its platform version, and its Work Queue Manager categories with their queue lengths.
They mark a target offline to take it out of use without deleting it, and online again later.

**Why this priority**: Without a known, observable target nothing can be placed on it. It is also
the "manage targets (online/offline, load)" half of the idea on its own.

**Independent Test**: With the demo environment up, register the second instance through the API,
read its status with the operator's credential for it, and compare version and queue lengths with
the same reads made directly on that instance. Stop it and read the status again: unreachable, with
the transport error verbatim.

**Acceptance Scenarios**:

1. **Given** no target named `iris-target`, **When** the operator registers it with a valid base
   address, **Then** it is listed with that name, address, description and `online: true`, and no
   credential appears anywhere in the stored record or the response.
2. **Given** a registered target, **When** the operator registers another one with the same name,
   **Then** the request is refused with a stated reason and the first is unchanged.
3. **Given** a base address that is not HTTPS and not a loopback address, **When** the operator
   registers it without the development allowance enabled, **Then** it is refused with a stated
   reason; with the allowance enabled it is accepted.
4. **Given** a reachable target and the operator's credential for it, **When** the operator reads
   its status, **Then** the response carries `reachable: true`, the version and the categories with
   queue lengths exactly as the target returned them, and when they were read.
5. **Given** a target that is down, **When** the operator reads its status, **Then** the response
   carries `reachable: false` and the transport error verbatim; no version or categories are
   invented.
6. **Given** a reachable target that refuses the operator's credential, **When** the operator reads
   its status, **Then** the response carries the target's HTTP status and reason verbatim.
7. **Given** an online target, **When** the operator sets it offline, **Then** it is listed with
   `online: false`; setting it online restores it. The flag is the product's own and is never
   inferred from reachability.
8. **Given** a registered target, **When** the operator edits its address or description or deletes
   it, **Then** later reads reflect the change; a run already in progress keeps the address it
   started with.

---

### User Story 2 — Run a step on a target and get its result on the primary (Priority: P1)

An operator places a platform-executed step (for example an integrity check) on a target by setting
the step's optional `target` to the target's name. At dispatch they provide, besides their local
credential, one credential of their own per target the flow uses. The run starts the platform job
on the target, follows it through the same states and live events as a local step, and on
completion keeps the step's `result` on the primary. Each step run records `executedOn` (the
target's name, or local) next to `executedAs`.

**Why this priority**: This is the idea's core: offload heavy work, keep control and results on the
primary.

**Independent Test**: The demo flow — two integrity checks locally and one on `iris-target`, fanning
into a final step — dispatched with a credential for `iris-target`, completes; the run read shows
`executedOn` correct for every step and the remote step's `result` equal to what the target's own
job read returns.

**Acceptance Scenarios**:

1. **Given** a step without `target`, **When** the flow is validated, dispatched and read,
   **Then** behaviour is exactly today's, and `executedOn` reports local.
2. **Given** a flow with one step on an online, reachable target and the operator's credential for
   that target, **When** it is dispatched, **Then** the platform job starts on the target (not on
   the primary), the step moves `queued` → `running` → `succeeded` with the same live events as a
   local step, `executedOn` is the target's name, `executedAs` is the operator, and the step's
   `result` holds what the target reported.
3. **Given** the same flow, **When** the target's job fails, **Then** the step is `failed` with the
   target's reason verbatim, and the rest of the run continues per the existing wave rules.
4. **Given** the remote step is running, **When** the operator cancels or pauses it (or the run),
   **Then** the request is forwarded to the target with the operator's credential for it, and the
   target's answer decides the outcome as it does locally.
5. **Given** the run's credential for a target expires during a long step, **Then** it is renewed
   from that target's own refresh credential, as the local run credential is today.
6. **Given** the run ends (any terminal state), **Then** every credential it held for any target is
   erased.

---

### User Story 3 — Refusals before and during the run (Priority: P1)

Every way a target can be unusable is reported as a value, per step, before any work starts where
possible, and as the step's failure reason when it happens mid-run.

**Why this priority**: A distributed run that fails silently or fails the whole wave for one target
is worse than no distribution. Constitution III and IV.

**Independent Test**: Unit tests with one management-API test double per target cover every code
below; on the demo environment, stopping `iris-target` while its step runs fails only that step,
after its timeout, with the transport error.

**Acceptance Scenarios**:

1. **Given** a step whose `target` names no registered target, **When** the flow is validated or
   dispatched, **Then** the report carries `TARGET_NOT_FOUND` with the `stepId`.
2. **Given** a step on an offline target, **Then** validation and dispatch report `TARGET_OFFLINE`
   with the `stepId`.
3. **Given** a step on a target that cannot be reached, **Then** the report carries
   `TARGET_UNREACHABLE` with the `stepId` and the transport error verbatim.
4. **Given** a step of a declared in-process type (`storage-headroom-check`, `db-size-report`,
   `switch-journal`, `purge-task-history`) on any target, **Then** the report carries
   `STEP_TYPE_NOT_REMOTE_CAPABLE` with the `stepId`.
5. **Given** a step type the target's own answers show it cannot run (for example the step's
   database or category does not exist there), **Then** the report carries the existing code for
   that condition with the `stepId`, based on the target's answer, not the primary's.
6. **Given** a flow using a target, **When** it is dispatched without a credential for that target,
   **Then** dispatch is refused with `TARGET_CREDENTIAL_MISSING` naming the target (and the steps
   using it), and no run is created.
7. **Given** a credential for a target that belongs to a user other than the dispatching operator,
   **Then** dispatch is refused with `TARGET_CREDENTIAL_USER_MISMATCH` naming the target, and no
   run is created.
8. **Given** a remote step is running, **When** the target becomes unreachable, **Then** only that
   step fails, after its step timeout, with the transport error kept verbatim; the other steps of
   the wave are unaffected.
9. **Given** the target refuses a call during the run (for example the operator lacks a privilege
   there), **Then** that refusal, status and reason verbatim, is the step's failure reason.

---

### Edge Cases

- A target is edited (new address) or deleted while a run uses it: the run keeps the address it
  started with and completes or fails on it; new validations use the new state.
- A target is set offline while a run uses it: running steps continue; new dispatches are refused.
- The same instance registered twice under different names: allowed; the product does not detect
  it (no discovery).
- A target registered with the primary's own address: allowed and treated as remote (useful for
  tests); `executedOn` is the target's name.
- The status read returns categories the operator cannot see: reported exactly as returned, never
  completed from the primary's view.
- A flow uses two targets and the credential for one is valid and the other missing: dispatch is
  refused as a whole; no partial run.
- A destructive platform-executed type (`purge-audit-records`) on a target: the existing typed
  confirmation still applies; the value to type is the one the step names (validated by the
  target's answer, not the primary's).
- The operator's local and target user names differ in letter case only: treated as the same user,
  as the local run credential check does today.

## Requirements *(mandatory)*

### Functional Requirements

**Target registry**

- **FR-001**: The system MUST let an operator create, list, read, update and delete target
  servers, each with a unique name, a base address (scheme, host, port) and an optional
  description.
- **FR-002**: The system MUST NOT persist any credential, token or password for a target, in the
  registry or anywhere else.
- **FR-003**: The system MUST refuse a base address that is not HTTPS unless it is a loopback
  address or an explicit, documented development allowance is enabled on the primary.
- **FR-004**: Each target MUST carry an `online` flag set only by an operator. An offline target
  MUST be refused at validation and dispatch (`TARGET_OFFLINE`). The flag MUST NOT be changed
  automatically from reachability.

**Target status and load**

- **FR-005**: The system MUST provide a status read per target, made against the target at the
  moment of the request with the operator's credential for that target, returning: reachable or
  not, the platform version, and the Work Queue Manager categories with their queue lengths, each
  value exactly as the target reported it, plus the time of the read.
- **FR-006**: When the target cannot be reached, the status read MUST return `reachable: false` and
  the transport error verbatim. When the target refuses, it MUST return the target's status and
  reason verbatim. No value MUST be invented, cached across requests or taken from the primary.

**Placing a step on a target**

- **FR-007**: A step MUST accept an optional `target` naming a registered target. Absent means
  local, with today's behaviour unchanged.
- **FR-008**: Only platform-executed step types MAY run on a target in v1. A declared in-process
  type on a target MUST be reported as `STEP_TYPE_NOT_REMOTE_CAPABLE`. The step-type catalog MUST
  state, per type, whether it is remote-capable, so clients do not derive it.
- **FR-009**: Validation of a step on a target MUST check, in this order: the target exists
  (`TARGET_NOT_FOUND`), is online (`TARGET_OFFLINE`), is reachable (`TARGET_UNREACHABLE`, transport
  error verbatim), the type is remote-capable (`STEP_TYPE_NOT_REMOTE_CAPABLE`), and the step's own
  preconditions hold **by the target's answers** (existing codes). Every finding MUST carry the
  `stepId`.

**Dispatch, tracking and results**

- **FR-010**: Dispatch MUST accept one credential per target used by the flow, and MUST refuse the
  whole dispatch, with no run created, when one is missing (`TARGET_CREDENTIAL_MISSING`) or belongs
  to a user other than the dispatching operator (`TARGET_CREDENTIAL_USER_MISMATCH`), naming the
  target.
- **FR-011**: Every call made to a target MUST use the operator's own credential for that target.
  There MUST be no service account and no shared credential. Target credentials MUST be held in
  memory for the run only, renewed from that target's refresh credential as the local run
  credential is, and erased when the run reaches a terminal state.
- **FR-012**: A step on a target MUST start its platform job on that target and MUST be followed
  with the same states, transitions and live events as a local step.
- **FR-013**: Each step run MUST record `executedOn` (the target's name, or local) next to
  `executedAs`, and the run read MUST return it.
- **FR-014**: A remote step's `result` MUST be collected from the target and kept on the primary,
  returned by the run read as for local steps.
- **FR-015**: A refusal or failure reported by the target MUST become the step's failure reason
  verbatim (status and reason).
- **FR-016**: A target that becomes unreachable during a run MUST fail only the affected step,
  after that step's timeout, keeping the transport error verbatim. It MUST NOT fail the wave or
  the run by itself.
- **FR-017**: Cancel and pause of a remote step (or of a run containing one) MUST be forwarded to
  the target with the operator's credential for it; the target's answer decides the outcome.
- **FR-018**: A run MUST keep the target address it started with for its whole life, regardless of
  later edits or deletion of the target.
- **FR-019**: Local behaviour and every existing automated test MUST remain unchanged when no step
  uses a target.

**Signing in to a target (Clarifications Q1)**

- **FR-022**: The system MUST offer a sign-in to a target: given the operator's user name and
  password for that target, it forwards them to the target's own sign-in once and returns the
  target's credential pair (access and refresh) to the caller, or the target's refusal verbatim
  (status and reason). It MUST NOT persist, log or cache the password or the returned pair. The
  status read (FR-005) and dispatch (FR-010) use the pair this call returned.
- **FR-023**: Managing the registry (FR-001, FR-004) MUST be open to any signed-in operator, as
  saving flows is; no extra product-side permission is introduced. Every call to a target still
  carries only the operator's own credential for it (FR-011), so the target decides.

**Reproducibility and documentation**

- **FR-020**: The single documented start command MUST bring up a second platform instance
  reachable as `iris-target`, and a documented demo flow (two local integrity checks and one on
  `iris-target`, fanning in) MUST run from it.
- **FR-021**: The README MUST gain a section "Implements DPI-I-588 (Distributed Work Manager)"
  with a link to the idea, listing what is implemented (remote dispatch, status and results,
  target state and load, online/offline), what is deliberately different (closed catalog, no
  arbitrary code) and what is future (in-process steps on targets, mirror-role discovery,
  callbacks). `docs/limitations.md` MUST reflect the same limits.

### Interface (observable contract)

Additions to the product API; exact shapes are fixed in `contracts/` by the plan.

| Call | Purpose |
|---|---|
| `GET /targets`, `POST /targets` | List, register |
| `GET /targets/{name}`, `PUT /targets/{name}`, `DELETE /targets/{name}` | Read, edit, delete |
| `GET /targets/{name}/status` | Reachable, version, categories with queue length, as the target reported them (operator's credential for that target) |
| `POST /targets/{name}/online` with `{"online": true\|false}` | Set the product-side flag |
| `POST /targets/{name}/sign-in` with the operator's user name and password for that target | The target's credential pair, or its refusal verbatim; nothing kept (FR-022) |
| Step schema: optional `target` | Place a step |
| Step-type catalog: remote-capable per type | Let clients offer only capable types (FR-008) |
| Run read: `steps[].executedOn` | Where each step ran |
| `/flows/{id}/dispatch` body: `targetCredentials: [{"target", "refreshToken"}]` | One credential per target used |

New error codes, each with `stepId` (or the target name for dispatch refusals):
`TARGET_NOT_FOUND`, `TARGET_OFFLINE`, `TARGET_UNREACHABLE`, `STEP_TYPE_NOT_REMOTE_CAPABLE`,
`TARGET_CREDENTIAL_MISSING`, `TARGET_CREDENTIAL_USER_MISMATCH`.

### Key Entities

- **Target server**: a named, reachable instance of the platform. Name (unique), base address,
  description, `online` flag, created/updated times. Never a credential.
- **Target status** (not stored): reachable, version, categories with queue lengths, read time, or
  the transport error / refusal. Always read live.
- **Step** (existing): gains an optional reference to a target by name.
- **Step run** (existing): gains `executedOn`; for a remote step it also keeps the target address
  used and the target's job identifier.
- **Run target credential** (not persisted beyond the run): per run and target, the operator's
  credential pair, renewed during the run and erased at its end.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the demo environment, the demo flow (2 local + 1 remote integrity checks, fanning
  in) completes, and `executedOn` is correct for 100 % of its steps.
- **SC-002**: The remote step's `result` on the primary equals the target's own job read for that
  job, field for field.
- **SC-003**: Stopping the target while its step runs fails exactly one step, with the transport
  error verbatim, and every local step of the run reaches the state it would have reached without
  the target.
- **SC-004**: Each of the six new error codes is produced by at least one automated test and by one
  recorded API call, each carrying the `stepId` or target name.
- **SC-005**: A search of stored data and logs after a full demo run, including target sign-ins,
  finds no password, token or refresh credential for any target.
- **SC-006**: A target's status read returns version and queue lengths equal to the same reads made
  directly on the target, in under 3 seconds when it is reachable.
- **SC-007**: The existing automated suites (backend, frontend unit and e2e) pass with the same
  counts plus the new tests; none is removed.
- **SC-008**: A stranger with a clean checkout brings up both instances with the single documented
  command and runs the demo flow by following the quickstart alone.

## Assumptions

- Targets run the same platform with its management API enabled, and the operator has an account
  of the **same user name** on each target they use. SentaiTask does not need to be installed on a
  target in v1.
- Authorization on a target is decided by the target alone (Constitution III); the primary never
  predicts it.
- "Reachable" means the target's management API answered at the transport level within a bounded
  time; the bound is a plan decision.
- A remote step's timeout is the step's own declared timeout, or the product's default when none is
  declared, as for in-process steps today.
- The Work Queue Manager category a step names must exist on the target (checked by the target's
  answer); the product does not create it there.
- The demo's second instance is on the same container network as the primary; HTTP between them is
  allowed only through the documented development allowance (FR-003).
- The spec 003 follow-ups on cancellation forwarding (T075) and category existence at validation
  (T076) apply equally to local and remote steps; the plan decides whether they are done here.

## Dependencies

- Spec 005 (run credential, refresh and user check) is the pattern extended per target.
- Spec 001 evidence (async job start, read, pause, cancel on the management API) is the contract
  used against each target.
- Spec 009 (canvas) depends on this spec's `contracts/`.
