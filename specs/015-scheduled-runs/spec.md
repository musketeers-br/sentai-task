# Feature Specification: Scheduled Runs That Execute

**Feature Branch**: `015-scheduled-runs`

**Created**: 2026-09-28

**Status**: Implemented

**Status note**: 25/25 tasks; regression record in evidence/.

**Input**: Competitor analysis (2026-09-28), risk 3: `/schedule` registers native tasks, but a
scheduled run cannot authenticate to the platform, so scheduling "is not a supported execution
path" (README, `docs/limitations.md`). For an application whose purpose is scheduled maintenance,
this is the most visible functional gap. The team chose (clarification Q1) to keep the scheduled
run's credential in the **IRIS Wallet**, the platform's own secret store, protected by a platform
resource. Other gaps found in the current scheduling code: the native task always fires daily at
midnight starting tomorrow, whatever the operator typed; the "next run" shown is the current time;
scheduling again creates duplicate tasks; there is no way to unschedule; and one native task is
created per step, although only the first one does anything.

## Context and Problem

An operator composes a nightly flow and chooses *Schedule*. Today:

1. **Nothing runs.** At fire time, the run has no credential. Validation cannot read the WQM
   categories, and management-API steps get 401. The canvas warns that scheduling is a v1
   limitation.
2. **The schedule typed is ignored.** "WEEKLY SAT 03:00" is stored as text; the platform task fires
   daily at 00:00.
3. **Scheduling is a one-way door.** Scheduling again adds more tasks, nothing removes them, and
   the Task Manager fills with one task per step, of which all but the first do nothing.
4. **Nobody sees scheduled runs.** A scheduled run would have no place in the canvas where the
   operator finds it later (spec 012 provides the history).

## Objective

An operator schedules a flow with a clear schedule (daily, weekly, monthly or every few hours, at a
given time) and a run-as account whose password is verified and kept only in the platform's wallet.
At each firing, the flow runs exactly as a *Run now* would, on the primary and on target servers,
and appears in the run history marked as scheduled. The operator sees the next run, the last
scheduled outcome, and can change the schedule, renew the credential or unschedule, leaving no
residue.

## Clarifications

### Session 2026-09-28

- Q: How does a scheduled run authenticate? → A: With a run-as account chosen at scheduling time,
  whose password the operator types once. The product verifies it with the platform and stores it
  only in the IRIS Wallet, in a collection protected by a platform resource. At fire time the run
  reads it through the platform (which checks the run-as account may use that collection), signs in
  as a normal operator would, and proceeds like *Run now*. The product never stores the password in
  its own data, logs or run records.
- Q: Does this change the constitution? → A: It requires a review (a change in how calls are
  authenticated). The team's position: Principle III is kept, because the platform still decides
  every call and every read of the secret, and nothing about permissions is cached. The Plan adds
  a clarifying amendment that allows an application to keep an authentication secret only in the
  platform's own secret store, never in its own storage.
- Q: Which schedules are offered? → A: Daily at a time; weekly on chosen days at a time; monthly on
  a day of the month at a time; every N hours (1–12) within the day starting at a time. These map
  to what the platform's Task Manager supports. Free-text schedules are no longer accepted.
- Q: Which steps may be scheduled? → A: Every available non-destructive step, including in-process
  and remote steps and the report steps of spec 013. Destructive steps remain refused, because a
  scheduled run cannot give the typed confirmation.
- Q: What happens when a scheduled run cannot start (wrong password, account not allowed to use the
  wallet collection, validation failure)? → A: A run is recorded as failed and marked scheduled,
  with the platform's reason verbatim in its log. The native task also reports the error, so the
  platform's own task history shows it.
- Q: One native task per flow or per step? → A: One per flow. This supersedes spec 003 FR-031 ("one
  task identifier per scheduled step"), whose extra tasks never did anything.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Schedule a flow and it actually runs (Priority: P1)

An operator opens *Schedule*, picks "Daily at 03:00", confirms the run-as account (their own name
by default), types its password (and the password for each target server the flow uses), and
schedules. The product verifies the passwords, stores them in the wallet, and creates one native
task with that timing. At 03:00 the flow runs, and the next morning the run is in the history,
completed, marked *scheduled*, with its log.

**Why this priority**: This is the whole feature. Without it, "scheduled maintenance" is only a
promise.

**Independent Test**: Schedule the spec 010 example to run two minutes from now; wait; the *Runs*
screen shows a new run marked scheduled, dispatched by the run-as account, completed, with a log
whose first entry says it was started by the schedule.

**Acceptance Scenarios**:

1. **Given** a valid, non-destructive flow, **When** the operator schedules it with a schedule, a
   run-as account and the correct passwords, **Then** the product verifies each password with the
   instance it belongs to, stores each in the wallet, creates one native task with that timing and
   run-as account, and answers with the task and the next run time as the platform reports it.
2. **Given** the schedule's time arrives, **Then** a run starts within the platform scheduler's
   granularity (one minute), runs every step as *Run now* would (local, in-process, remote and
   report steps), renews its credential while it runs, and ends with the same outcome rules.
3. **Given** a scheduled run, **Then** the history marks it as *scheduled*, dispatched by the run-as
   account, and its first log entry says it was started by the schedule of flow *name*.
4. **Given** a wrong password, **When** the operator schedules, **Then** nothing is stored or
   created, and the platform's refusal is shown verbatim next to the password it concerns.
5. **Given** the operator may not create tasks, or may not write to the wallet collection, **Then**
   nothing is left behind (no task, no secret), and the platform's refusal is shown verbatim.
6. **Given** the flow contains a destructive step, **Then** scheduling is refused as today, naming
   the step.

---

### User Story 2 - See, change and remove a schedule (Priority: P1)

An operator opens *Schedule* on a scheduled flow and sees its current schedule, run-as account,
next run and the outcome of the last scheduled run (with a link to it). They can change the
timing, renew the stored passwords, or unschedule. Unscheduling removes the native task and the
stored secrets. Scheduling again replaces, never duplicates.

**Why this priority**: Without it, scheduling leaves residue in the platform and the operator
cannot trust what is scheduled. It is also where a failing schedule (for example after a password
change) is fixed.

**Independent Test**: Schedule a flow; schedule it again with another time: the Task Manager has
one task for it, with the new time. Unschedule: no task and no secret for the flow remain.

**Acceptance Scenarios**:

1. **Given** a scheduled flow, **When** the operator opens *Schedule*, **Then** it shows the
   schedule in words ("Weekly on Sat at 03:00"), the run-as account, the next run from the
   platform, and the last scheduled run's outcome and time with a link to it.
2. **Given** a scheduled flow, **When** the operator changes the timing and saves, **Then** the one
   native task is updated (or replaced) with the new timing, and no second task exists.
3. **Given** a scheduled flow, **When** the operator enters new passwords (*Renew credential*),
   **Then** they are verified and replace the stored ones; the timing is unchanged.
4. **Given** a scheduled flow, **When** the operator unschedules, **Then** its native task and all
   its stored secrets are removed, and the flow shows as not scheduled.
5. **Given** a flow scheduled by an earlier version (one task per step), **When** it is scheduled
   again or unscheduled, **Then** all its earlier tasks are removed too.
6. **Given** the flow list, **Then** each scheduled flow shows its next run as the platform reports
   it, not the time the list was read.

---

### User Story 3 - A scheduled run that cannot start says why (Priority: P2)

A scheduled run fires, but the run-as account's password was changed, or the account may no longer
use the wallet collection, or the flow no longer validates. The operator finds a failed scheduled
run in the history, whose log states the platform's reason. The platform's task history also shows
the error.

**Why this priority**: Unattended runs fail silently in most schedulers; here the failure must be
as visible as a success.

**Independent Test**: Schedule a flow, then change the run-as account's password on the platform;
at the next firing a failed scheduled run appears, whose log says the sign-in was refused, with the
platform's text.

**Acceptance Scenarios**:

1. **Given** the stored password no longer works, **When** the schedule fires, **Then** a run is
   recorded as failed and scheduled, with a log entry "Scheduled run could not sign in to <instance>:
   <platform text>", and no step runs.
2. **Given** the run-as account may not use the wallet collection, **Then** the recorded failure
   carries the platform's refusal to read the secret, verbatim.
3. **Given** the flow no longer validates at fire time (for example a category was removed),
   **Then** the recorded failure lists the validation errors as the validation report gives them.
4. **Given** a target server does not answer at fire time, **Then** the run starts and the remote
   step behaves as in a manual run (spec 008: back-off, timeout), rather than blocking the whole
   run.
5. **Given** any of these failures, **Then** the native task's run is marked as errored in the
   platform's own task history with the same reason.

---

### User Story 4 - The canvas schedule dialog is clear (Priority: P2)

The *Schedule* dialog offers a structured schedule picker instead of free text, explains where the
password is kept ("in this instance's IRIS Wallet, readable only by accounts the platform allows"),
asks for the target passwords the flow needs, and no longer shows the v1 limitation notice.

**Why this priority**: Operators must understand, before typing a password, where it goes and what
it allows.

**Independent Test**: Open *Schedule* on a flow with a remote step: the dialog shows the schedule
picker, the run-as account prefilled with the signed-in user, a password field for the primary and
one for the target, the wallet explanation, and no limitation notice.

**Acceptance Scenarios**:

1. **Given** the dialog, **Then** the schedule picker offers Daily, Weekly (day checkboxes), Monthly
   (day of month) and Every N hours (1–12), each with a start time, and shows the result in words
   before saving.
2. **Given** the flow has steps on target servers, **Then** the dialog asks for one password per
   target, under the same run-as account name (spec 008: same user name on each target).
3. **Given** the dialog, **Then** it states where passwords are stored and that removing the
   schedule removes them.
4. **Given** invalid input (no day chosen for Weekly, time out of range), **Then** the dialog shows
   the problem on the field and does not submit.
5. **Given** the dialog, **Then** passwords are never shown back, never pre-filled, and never kept
   in the browser after the dialog closes.

### Edge Cases

- The run-as account is not the signed-in operator: allowed if the platform allows the operator to
  create a task that runs as that account; the product verifies that account's password and does
  not judge.
- A scheduled run fires while a previous run of the same flow is still running: the new run starts
  anyway (as two manual dispatches would), and both appear in the history. Preventing overlap is out
  of scope.
- The instance restarts during a scheduled run: the run is left as after any restart today (the
  existing behaviour for manual runs); the next firing is unaffected.
- The flow is edited after scheduling: each firing runs the flow's current saved revision (as *Run
  now* does), validated at fire time.
- The flow is scheduled and then a destructive step is added: the firing is refused by validation at
  fire time and recorded as a failed scheduled run (US3-3).
- The wallet collection was deleted by an administrator: scheduling again recreates it if the
  operator may; a firing fails with the platform's reason.
- A target server is removed from the targets list after scheduling: the firing fails validation
  (target not registered) and is recorded.
- Clock and time zone: schedule times are the instance's local time, as the platform's Task Manager
  uses; the dialog says so.

## Requirements *(mandatory)*

### Functional Requirements

**Scheduling**

- **FR-001**: Scheduling MUST take a structured schedule (daily; weekly with days; monthly with day
  of month; every N hours with N in 1–12; each with a start time in the instance's local time), a
  run-as account, a password for the primary, and a password for each target server the flow's
  steps use.
- **FR-002**: Before storing anything, the product MUST verify each password by signing in to the
  instance it belongs to as the run-as account, and MUST show any refusal verbatim, storing nothing.
- **FR-003**: Passwords MUST be stored only in the IRIS Wallet of the primary instance, in a
  collection protected by a platform resource. They MUST NOT be written to the product's data,
  logs, run records, responses or browser storage.
- **FR-004**: The product MUST create exactly one native task per scheduled flow, running as the
  run-as account, with the timing of FR-001, through the platform's management API with the
  operator's credential (as today).
- **FR-005**: Scheduling a flow that is already scheduled MUST replace its task and secrets; the
  flow MUST never have more than one task. Tasks created by earlier versions for the same flow
  (one per step) MUST be removed.
- **FR-006**: If any step of scheduling fails, the product MUST leave no new task and no new secret
  behind, and MUST keep the previous schedule intact when replacing one.
- **FR-007**: Flows with destructive steps MUST remain unschedulable. In-process, remote and report
  steps MUST be schedulable.

**Firing**

- **FR-008**: At each firing, the product MUST read the stored credentials through the platform,
  sign in to each instance, validate the flow's current revision, and dispatch it exactly as a
  manual dispatch with a run credential and target credentials, so the run renews its credentials
  and follows every existing rule.
- **FR-009**: A scheduled run MUST be marked as triggered by the schedule, with the run-as account as
  its dispatcher, and its first log entry MUST say so.
- **FR-010**: When a firing cannot start (secret unreadable, sign-in refused, validation failed), the
  product MUST record a failed scheduled run with the reason verbatim in its log, and MUST report the
  error to the platform's task history.
- **FR-011**: Credentials obtained at firing MUST be erased when the run ends, as for manual runs.

**Managing a schedule**

- **FR-012**: The product MUST show, for a scheduled flow, its schedule in words, run-as account,
  next run (as the platform reports it) and last scheduled run (outcome, time, link).
- **FR-013**: The operator MUST be able to change the timing, renew the credentials and unschedule.
  Unscheduling MUST remove the native task(s) and every stored secret of the flow.
- **FR-014**: The flow list MUST show the next run as the platform reports it for scheduled flows.

**Canvas**

- **FR-015**: The *Schedule* dialog MUST provide the structured picker, the run-as account
  (prefilled with the signed-in user), the password fields (primary and one per target used), an
  explanation of where passwords are stored, the current schedule when there is one, and *Update*,
  *Renew credential* and *Unschedule* actions. The v1 limitation notice MUST be removed.
- **FR-016**: The history (spec 012) MUST show a *Scheduled* marker on scheduled runs and allow
  filtering by trigger (manual, scheduled).

**Documentation and governance**

- **FR-017**: The README and `docs/limitations.md` MUST describe scheduling as supported, with how
  credentials are stored and what the run-as account needs; the "scheduling is not operational"
  limitation MUST be removed.
- **FR-018**: The constitution MUST be reviewed for this change and the outcome recorded; any
  amendment follows its governance rules.

### Key Entities

- **Schedule**: flow, timing (kind, days, day of month, every N hours, start time), run-as account,
  native task id, created by, created at. No password.
- **Stored credential**: a wallet secret per (flow, instance), holding the run-as account's
  password, protected by the product's wallet collection resource.
- **Run trigger**: *manual* or *scheduled*, on each run (manual for all existing runs).
- **Start failure**: a run recorded as failed and scheduled, with no step runs and a log entry
  carrying the reason.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A flow scheduled to fire in 2 minutes starts within 60 seconds of its time and
  completes, in 100% of 5 test firings, including one with a remote step.
- **SC-002**: A scan of the product's globals, tables, logs, run records, API responses and browser
  storage after scheduling, firing and unscheduling finds the test password 0 times.
- **SC-003**: After 3 re-schedules and 1 unschedule of the same flow, the platform's Task Manager
  lists 0 tasks and the wallet 0 secrets for it.
- **SC-004**: When the run-as password is changed on the platform, the next firing produces a failed
  scheduled run whose log contains the platform's refusal, in 100% of test cases, and the task's
  platform history shows an error.
- **SC-005**: The next run shown by the canvas equals the platform's own next-run time for the task,
  in 100% of the schedule kinds tested (daily, weekly, monthly, every N hours).
- **SC-006**: An operator schedules a flow from the canvas in under 1 minute, without reading
  documentation.

## Assumptions

- The IRIS Wallet in IRIS 2026.2 can hold a secret usable for a sign-in and restrict who may use
  it through a resource, and its management API can create and delete secrets with the operator's
  credential (the Plan proves this first, including whether the secret can authenticate a request
  without the product reading its value).
- The platform lets a task run as an account other than its creator when the creator's privileges
  allow it; the product does not check.
- The run-as account needs, on each instance, the privileges its flow's steps need (as for a manual
  run), plus use of the product's wallet collection on the primary.
- Specs 012 (history, log) is merged first; this spec adds the trigger to it. Without 012, the
  scheduled run is still reachable by its link and the task history.
- Preventing overlapping runs, calendars with exceptions, and time-zone conversion are out of scope.
