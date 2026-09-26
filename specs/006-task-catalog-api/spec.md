# Feature Specification: Task Catalog API (backend)

**Feature Branch**: `006-task-catalog-api`

**Created**: 2026-09-26

**Status**: Draft

**Input**: Make the existing task-catalog API tell the truth about the platform's Task Manager, so
the canvas (spec 007) can offer a management-portal view of it. Backend only; same philosophy as
spec 004 — the API states only what the platform provably delivers.

## Context and Problem

The contest theme is "Build Your Own Management Portal". Seeing and controlling the platform's
Task Manager from SentaiTask is exactly that. The product already exposes three catalog calls
(list tasks, read one task, suspend/resume a task), but what they return does not match the
platform:

| Field / call today | What it really is | Source of truth available |
|---|---|---|
| `className` | the list's `Type` ("System"/"User"), not a class | single read carries `TaskClass` (spec 001 evidence 04) |
| `runAsUser` | always empty | single read carries `RunAsUser` (evidence 04) |
| `isDestructive` | always false | derivable from the step-type catalog when the class is one it knows |
| `state` | invented: suspended → "cancelled", otherwise "queued" | info read carries `Status`, `Error`, `LastStarted`, `LastFinished` (evidence 05) |
| suspend / resume | calls an endpoint never validated against the platform | to be proven on the real instance |
| tasks created by SentaiTask | indistinguishable from any other | their names follow `SentaiTask: <flowId>#<stepId>` |
| "last 5 runs" (prototype) | not provided | only if a platform read is proven |

A real case on 2026-09-25: a flow scheduled from the canvas created three tasks
`SentaiTask: 1#01..03` due to fire at midnight and fail (spec 004 D-2). An operator could only see
them in the platform's own portal or with raw API calls.

## Objective

Every value the catalog API returns about a task is the platform's own value, or it is not
returned. An operator (through the API now, through the canvas in spec 007) can list the
platform's scheduled tasks, see what each one really is and how it last went, recognise the ones
SentaiTask created, and suspend or resume a task — the last only if the platform's contract for it
is proven.

## Scope

### In scope

1. Correct each field in the table above from the platform's own reads, or remove it.
2. Prove, on the real instance, how the platform suspends and resumes a task; make the product's
   suspend/resume call use exactly that, or answer with an explicit "not supported" error.
3. Mark tasks created by SentaiTask with the flow and step they belong to.
4. Make the list's filters (text, namespace, scheduled/suspended, destructive only) operate on the
   corrected data.
5. Recent run history per task — only if a platform read for it is proven.

### Out of scope

- Any UI (spec 007).
- Creating, editing or deleting tasks; "run now" for a native task.
- Changing how SentaiTask schedules flows (spec 004 D-2, E-3 unchanged).
- New endpoints, unless the plan justifies one; all field changes are additive except removing
  values that are false.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — See what each task really is (Priority: P1)

An operator lists the platform's tasks and, for each one, sees its real class, the user it runs as,
its namespace, its next and last run, its current status and last error — exactly as the platform
reports them.

**Why this priority**: every other capability (filtering, suspending, the canvas screen) is only as
good as this data; today three of its fields are false.

**Independent Test**: For every task on the real instance, each returned value equals what the
platform's own reads report for that task; no field is invented.

**Acceptance Scenarios**:

1. **Given** the instance's built-in "Integrity Check" task, **When** the operator reads the
   catalog, **Then** its class is the platform's task class (not "System"), its run-as user is the
   platform's value, and its status and last error are the platform's values verbatim.
2. **Given** a task whose last run failed, **When** listed, **Then** the platform's error text is
   returned verbatim.
3. **Given** a task whose class is one the step-type catalog knows as destructive (e.g. the audit
   purge), **When** listed, **Then** it is marked destructive; a task of an unknown class is marked
   not destructive **and** flagged as "destructiveness unknown".
4. **Given** the operator reads one task, **Then** the single-task read returns the same corrected
   values as the list for that task.

---

### User Story 2 — Recognise what SentaiTask scheduled (Priority: P1)

An operator sees, among the platform's tasks, the ones SentaiTask created, and which flow and step
each belongs to.

**Why this priority**: the real case of 2026-09-25 — tasks created by the product that will fail
were invisible from the product.

**Independent Test**: After scheduling a flow, the catalog lists one task per step, each marked as
created by SentaiTask with that flow's id and the step's id; tasks created outside SentaiTask are
not marked.

**Acceptance Scenarios**:

1. **Given** tasks named `SentaiTask: 1#01`, `1#02`, `1#03`, **When** listed, **Then** each is
   marked as created by SentaiTask with flow `1` and steps `01`, `02`, `03`.
2. **Given** a task whose name merely starts with "SentaiTask" but does not follow the pattern,
   **When** listed, **Then** it is not marked.
3. **Given** a marked task whose flow no longer exists in SentaiTask, **When** listed, **Then** it
   is still marked, with the flow flagged as not found.

---

### User Story 3 — Suspend and resume a task (Priority: P2)

An operator suspends a task (e.g. the three that would fail at midnight) and later resumes it; the
change is the platform's, visible on the next read.

**Why this priority**: the only control the catalog offers; valuable, but only if the platform's
contract is proven.

**Independent Test**: On the real instance, suspend a task → the platform reports it suspended and
it no longer shows a next run; resume it → the platform reports it active again.

**Acceptance Scenarios**:

1. **Given** the suspend contract is proven, **When** the operator suspends a task, **Then** the
   platform reports it suspended on the next read, and the call succeeds.
2. **Given** a suspended task, **When** the operator resumes it, **Then** the platform reports it
   active on the next read.
3. **Given** the platform refuses (insufficient privilege, unknown task), **When** the operator
   suspends, **Then** the refusal and the platform's reason are returned verbatim.
4. **Given** the suspend contract could **not** be proven on the real instance, **When** the
   operator calls suspend or resume, **Then** the call answers with an explicit "not supported on
   the target platform" error and changes nothing; the README says why.

---

### User Story 4 — Filter the corrected catalog (Priority: P2)

An operator narrows the list by text, namespace, scheduled/suspended and destructive only, and the
count shows how many matched out of how many exist.

**Why this priority**: the prototype's toolbar; useful once the data is true.

**Independent Test**: Each filter, alone and combined, returns exactly the tasks whose corrected
values match, with a correct "N of M" count.

**Acceptance Scenarios**:

1. **Given** "destructive only", **When** listed, **Then** only tasks marked destructive (User
   Story 1 scenario 3) are returned.
2. **Given** "suspended", **When** listed, **Then** only tasks the platform reports suspended are
   returned.
3. **Given** a text filter, **When** listed, **Then** matching is case-insensitive over name and
   class.

---

### User Story 5 — Recent runs of a task (Priority: P3, conditional)

An operator reading one task sees its recent runs (when, how long, outcome).

**Why this priority**: in the prototype, but only if the platform offers a proven read for it.

**Independent Test**: If a platform read for task history is proven, the single-task read returns
up to 5 recent runs matching the platform's history; if not, the field is absent and the README
says why.

**Acceptance Scenarios**:

1. **Given** a proven history read and a task that ran, **When** read, **Then** up to 5 recent runs
   are returned with start, end and outcome as the platform reports them.
2. **Given** no proven history read, **When** read, **Then** no history field is returned (not an
   empty list pretending there is none).

### Edge Cases

- **Task deleted between list and read**: the single read answers "not found", as today.
- **Platform read partially fails** for one task (e.g. its info read is refused): that task is
  still listed with the values that were read, and the missing ones are absent and flagged as
  unavailable with the platform's reason — never filled in.
- **Operator without privilege to read tasks**: the platform's refusal is returned verbatim for the
  whole call (Constitution III).
- **Platform timestamps and empty values** (e.g. no next run, "Runs After #1"): returned as the
  platform gives them, never reformatted into something else.
- **Many tasks** (the prototype shows 148): the list still answers within the success criterion.
- **Tasks in namespaces the operator cannot access**: whatever the platform returns is what is
  shown.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001 — Real class.** Each task's class is the platform's own task class for that task.
- **FR-002 — Real run-as user.** Each task's run-as user is the platform's value.
- **FR-003 — Real status.** Each task carries the platform's status, last error, last started and
  last finished values verbatim; the invented `state` value is no longer returned.
- **FR-004 — Destructiveness.** A task is marked destructive when its class is one the step-type
  catalog declares destructive; tasks of classes the catalog does not know carry an explicit
  "destructiveness unknown" flag instead of a guess.
- **FR-005 — SentaiTask origin.** Tasks whose name follows `SentaiTask: <flowId>#<stepId>` carry
  the flow and step ids and whether that flow exists in SentaiTask; no other task is marked.
- **FR-006 — Suspend/resume proven or refused.** Suspend and resume use exactly the platform
  contract proven on the real instance, with the platform's refusals returned verbatim. If no
  contract is proven, both answer an explicit "not supported on the target platform" error and
  change nothing.
- **FR-007 — Filters on true data.** Text, namespace, scheduled/suspended and destructive-only
  filters operate on the corrected values; the response states how many matched and how many
  exist.
- **FR-008 — History only if proven.** Recent runs (up to 5) are returned by the single-task read
  only when a platform read for them is proven; otherwise the field is absent.
- **FR-009 — Partial reads are visible.** When a per-task platform read fails, the values it would
  have given are absent and the task is flagged with the platform's reason; nothing is filled in.
- **FR-010 — Compatibility.** No flow-document change; field additions are additive; the only
  removals are values that were false (`state` as invented, `className` from `Type`). Existing
  tests pass, adjusted only where they encoded those false values; none deleted.

### Key Entities

- **Catalog task**: a platform scheduled task as the product reports it — id, name, namespace,
  class, run-as user, next run, last started, last finished, status, last error, suspended,
  destructive (or unknown), SentaiTask origin (flow id, step id, flow exists), and — only if proven
  — recent runs.
- **SentaiTask origin**: the link from a platform task back to the flow and step that created it.
- **Recent run** (conditional): start, end, outcome of one past execution, as the platform reports.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For **100%** of tasks on the real instance, every returned class, run-as user,
  status and last-error value equals the platform's own reads for that task (field-by-field
  comparison recorded as evidence).
- **SC-002**: **0** invented values: no field returned for a task that the platform did not report.
- **SC-003**: After scheduling a flow of N steps, the catalog shows exactly **N** tasks marked with
  that flow and their step ids.
- **SC-004**: Suspend then resume of one task is confirmed by the platform's own read after each
  call — or, if the contract is not proven, both calls are refused with the explicit error and the
  task is unchanged.
- **SC-005**: The full list for the instance (≈ 20 tasks today; up to 150 in the prototype)
  answers in under **2 seconds** on the dev container.
- **SC-006**: Delivered within ~5 tasks.

## Assumptions

- The platform's per-task reads (single read and info read, spec 001 evidence 04/05) are the
  sources of truth; the list read alone does not carry class, run-as user or status.
- The step-type catalog (spec 004/005) is the only source for "destructive"; a platform class
  outside it is not guessed.
- The name pattern `SentaiTask: <flowId>#<stepId>` is the one the product itself uses when
  scheduling (spec 003) and is not produced by anything else.
- The operator's own credential is used for every platform read and for suspend/resume
  (Constitution III); the platform decides what they may see and do.

## Dependencies

- Spec 001 evidence 03/04/05 (list, single and info reads).
- Step-type catalog (specs 004/005) for destructiveness.
- Real IRIS 2026.2 container for SC-001, SC-004, SC-005 and the suspend/history proofs.
- Spec 007 for the operator-facing screen.
