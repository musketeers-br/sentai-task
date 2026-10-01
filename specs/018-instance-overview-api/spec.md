# Feature Specification: Instance Overview API — Every Contest Area Readable on Demand

**Feature Branch**: `018-instance-overview-api`

**Created**: 2026-09-29

**Status**: Implemented <!-- Draft | Planned | In Progress | Implemented | Merged | Superseded by NNN — see "Spec status" in AGENTS.md -->

**Status note**: 2026-09-29. 38/38 tasks; the T029 spike passed, so process actions shipped (T034 not
needed). Suite 440/440; live quickstart and spike evidence in evidence/README.md. The canvas screens
are spec 019.

**Input**: User description: "Instance Overview API (backend). Backend only; the canvas screens are
spec 019. A closed, named set of on-demand readings over the platform's management API (processes,
locks, shared memory, activity, devices, licenses, web sessions), a per-area summary for an overview
screen, the four spec 013 reports runnable without a flow, a way to turn a reading into a one-step
flow, and — only after a spike records their contract — process suspend, resume and terminate.
Not a generic proxy; the operator's own credential and the platform's verbatim refusal on every call."

## Context and Problem

1. **Four of the contest's six areas are only reachable through a flow.** Spec 013 (clarification
   Q2: "steps, not pages") made security, web applications, alerts and secrets readable as report
   steps. That decision stands, and it is what makes those checks schedulable and runnable on target
   servers. But an operator who just wants to *look* — "who is connected, what is locked, how much
   shared memory is left" — has to compose a flow, validate it, run it and open a step's result.
   Judges and first-time users read that as missing coverage.
2. **The operating-system area is covered only by disk readings.** `storage-headroom-check` and
   `db-size-report` cover databases and journal directories. Processes, locks, memory, devices and
   license use are not covered at all.
3. **The platform already answers all of it.** The management API's own description
   (`GET /api/mgmnt/v1/%SYS/spec/api/admin`) lists 305 operations; SentaiTask uses about 26. Probed
   read-only on 2026-09-29:

   | Area | Platform read | Answer on the dev container |
   |---|---|---|
   | Processes | `GET /v2/processes` | 200, 65 rows: job, process id, user, device, namespace, routine, commands, global references, state, client |
   | Locks | `GET /v2/locks` | 200, 66 rows: owner process, mode, reference, directory, removable |
   | Shared memory | `GET /v2/monitor/system-usage/shared-memory` | 200, 28 rows: allocated, available, used |
   | Activity | `GET /v2/monitor/system-usage`, `GET /v2/monitor/dashboard/main` | 200: global references, block reads/writes, journal entries, uptime, last backup, busy processes |
   | Resource contention | `GET /v2/monitor/dashboard/system-resources` | 200, 56 rows of seize counters |
   | Licenses | `GET /v2/monitor/license-usage` | 200: summary, use by process, use by user |
   | Devices | `GET /v2/devices` | 200, 12 rows |
   | Web sessions | `GET /v2/web-sessions` | 200, 1 row |

4. **The API has no host CPU, no host memory and no console log.** Nothing in the 305 operations
   reports host CPU percentage, host RAM or `messages.log`. The "operating system" area can honestly
   be offered only as *instance resources*; any label promising host CPU would be false.
5. **Process actions exist but are unproven.** `POST /v2/process/suspend`, `/resume`, `/terminate`
   and `/broadcast` are in the description; none was exercised. Spec 001's lesson applies: the
   published description and the platform's behaviour differed in six places (authentication shape,
   `v1` locations, query-string names, required fields), so no write is promised before it is probed.

## Objective

Through the product's API, an operator can read each instance resource area on demand, get a
one-call summary of every area for an overview screen, run any of the four spec 013 reports without
building a flow, and turn what they just read into a one-step flow they can validate and schedule.
Every read uses the operator's own credential; what the platform refuses is returned as it said it,
area by area, without failing the areas it allowed. Process actions follow only if a spike shows the
platform's contract is usable, and terminate needs a typed confirmation.

## Clarifications

### Session 2026-09-29

- Q: Does the summary run the four spec 013 reports in full, or only cheap counts? → A: Cheap
  counts only. Report areas show counts from one inexpensive read each (enabled accounts, web
  applications, wallet collections, the dashboard's alert counters); findings by severity appear
  only when the operator runs the report on demand (User Story 3).
- Q: Do process actions stay in this spec or move to their own? → A: They stay here as P3, gated by
  the spike (FR-019), which is the first task of User Story 5; no P1 or P2 task depends on it, and a
  failed spike ends the story under FR-023.
- Q: Where is each process action recorded? → A: In the product's own small action record
  (operator, time, process id, action, the platform's answer verbatim), persisted and readable
  through the product's API. It never stores a permission outcome and does not depend on the
  platform's auditing being enabled; it is not a run and never appears on *Runs*.
- Q: Does this spec add step types for the instance areas so they can become scheduled checks? →
  A: No. The catalog is unchanged; the seven instance areas answer "no step type" when asked to
  become a flow. Instance-resource checks, with their own finding rules, are a later feature.

## User Scenarios & Testing *(mandatory)*

The operator in these stories uses the product's API directly (as the spec 008 operator did); the
canvas screens over it are spec 019. Each story is observable end-to-end with a single HTTP client.

### User Story 1 - Read one instance resource area on demand (Priority: P1)

An operator asks the product for one named reading — *processes*, *locks*, *memory*, *activity*,
*devices*, *licenses* or *web-sessions* — and gets the platform's current rows for it, in a stable
shape, read at that moment with their own credential.

**Why this priority**: It is the smallest slice that covers the contest's weakest area (operating
system) and the base every other story and the whole of spec 019 rest on.

**Independent Test**: With the stack up, sign in as `_SYSTEM`, request each of the seven readings,
and compare each answer with the platform's own read made at the same moment; then request an
unknown reading name and one reading as an operator the platform refuses.

**Acceptance Scenarios**:

1. **Given** a signed-in operator the platform allows to read processes, **When** they request the
   *processes* reading, **Then** they get one row per process with its process id, user, namespace,
   routine, state, commands and global references, and the time the reading was taken.
2. **Given** the same operator, **When** they request *memory*, **Then** each shared-memory row
   carries allocated, available and used amounts and the used share as a percentage the product
   computed from those two numbers.
3. **Given** an operator the platform refuses for that read, **When** they request the reading,
   **Then** the product answers with the platform's HTTP status and status object verbatim, and
   nothing else.
4. **Given** any operator, **When** they request a reading name that is not in the product's list
   (including a platform path or a name with a slash), **Then** the product refuses it as unknown
   without calling the platform.
5. **Given** any reading, **When** it is requested twice in a row, **Then** the platform is called
   both times (no reading or permission outcome is cached).

---

### User Story 2 - One summary of every area for an overview screen (Priority: P1)

An operator asks for the overview summary and gets, in one answer, one entry per area — the seven
instance readings plus the four report areas (security posture, web applications, system alerts,
secrets) — each with a short headline or its own failure.

**Why this priority**: This is what spec 019's landing screen shows. Without it, the screen would
need eleven calls and would have to decide in the browser which failures are fatal.

**Independent Test**: Request the summary as `_SYSTEM` (all areas succeed), then as an operator with
no security administration (security areas refused, instance areas succeed), and check that each
entry stands alone.

**Acceptance Scenarios**:

1. **Given** a fully privileged operator, **When** they request the summary, **Then** every area
   entry has an outcome of *ok* and a headline: process count and the busiest process by commands,
   lock count, shared-memory use as a percentage (the platform's total row, and the most used
   consumer), uptime and last backup, license units in
   use, device count, web session count, and for each report area a count from one inexpensive
   read: enabled accounts (security posture), web applications (web applications), serious alerts
   and application errors from the dashboard (system alerts), wallet collections (secrets). No
   report is run and no finding is computed by the summary.
2. **Given** an operator the platform refuses for some of the summary's reads (for example the
   accounts read behind `security`), **When** they request the summary, **Then** exactly the entries
   whose read was refused carry the platform's refusal verbatim, every other entry is *ok*, and the
   summary itself answers successfully.
3. **Given** the platform does not answer one of the reads, **When** the summary is requested,
   **Then** only that area reports *unreachable* with the transport error, and the rest are unaffected.
4. **Given** any summary, **When** it is returned, **Then** it states when each area was read and
   contains no password, token, secret value or password hash.

---

### User Story 3 - Run a spec 013 report without building a flow (Priority: P1)

An operator asks the product to run one of the four report step types on demand and gets the same
report — summary, rows and findings with severity — that a run would store for that step, without a
run being created.

**Why this priority**: It makes security, web applications, alerts and secrets visible in one call,
reusing reports that already exist and are tested, so the two paths can never disagree.

**Independent Test**: Run `security-posture-report` on demand and inside a one-step flow on the same
instance, one after the other, and compare the two reports; then check that no run was recorded by
the on-demand call.

**Acceptance Scenarios**:

1. **Given** a privileged operator, **When** they run `web-app-inventory` on demand, **Then** they
   get the same report structure and finding rules as the step produces in a run.
2. **Given** a report step's parameters (for example `failOnFindings`, or the thresholds of
   `system-alerts-check`), **When** they are supplied on demand, **Then** they are validated against
   that step type's declared parameter schema exactly as validation does for a flow, and an invalid
   value is refused with the same reason.
3. **Given** a step type that is not one of the catalog's platform-read report types (for example
   `integrity-check`, `purge-task-history` or an unknown name), **When** it is requested on demand,
   **Then** it is refused without calling the platform.
4. **Given** an on-demand report, **When** it completes, **Then** no run, step run or log entry has
   been created, and the run list is unchanged.
5. **Given** an operator the platform refuses for one of the report's reads, **When** the report is
   run on demand, **Then** the answer is a failed report carrying the platform's words verbatim, as
   the step would fail in a run.

---

### User Story 4 - Turn a reading into a scheduled check (Priority: P2)

From an area they have just read, an operator asks the product to create a flow holding one step of
that area's step type with the parameters they used. The new flow goes through the one validation
gate, so it can be scheduled with the existing schedule endpoint.

**Why this priority**: It keeps the product's thesis — orchestration, not pages — visible from the
overview: every look can become a recurring check. It depends on Stories 1–3 only for its entry point.

**Independent Test**: Create a flow from the *secrets* area, validate it, schedule it for a time a
minute ahead, and see the scheduled run produce the secrets inventory report.

**Acceptance Scenarios**:

1. **Given** an area that has a step type (the four report areas, each mapped to its spec 013
   type), **When** the operator asks to turn it into a flow, **Then** a new flow exists with one step of
   that type, the supplied parameters, a clear default name and a WQM category that exists, and it
   passes validation.
2. **Given** an area with no step type (processes, locks, memory, activity, devices, licenses, web
   sessions in this version), **When** the operator asks to turn it into a flow, **Then** the product
   refuses with a reason that says this area has no step type, and nothing is created.
3. **Given** a flow created this way, **When** it is scheduled, **Then** the existing schedule rules
   apply unchanged (destructive steps cannot be scheduled; the run-as account's password lives only
   in the platform's wallet).

---

### User Story 5 - Suspend, resume or terminate a process (Priority: P3)

An operator who has read the process list asks the product to suspend, resume or terminate one
process by its process id. Terminate requires the operator to type the process id again as a
confirmation. The platform decides; its answer is returned verbatim.

**Why this priority**: It is the one write the overview needs to be a management screen and not
only a report, but its contract is unproven. It ships only if the spike (FR-019) shows the platform
contract works as described; otherwise it is dropped and the limitation is documented.

**Independent Test**: Start a disposable process in a test namespace, suspend and resume it and read
its state after each, then terminate it with and without the typed confirmation.

**Acceptance Scenarios**:

1. **Given** the spike's evidence is recorded and a disposable process exists, **When** the operator
   suspends it, **Then** the product returns the platform's answer and a fresh read of that process
   shows its new state.
2. **Given** a terminate request without the typed process id, or with a different one, **When** it
   is sent, **Then** the product refuses it as needing confirmation (the same status the destructive
   step uses at dispatch) without calling the platform.
3. **Given** a terminate request with the matching typed process id, **When** the platform accepts
   it, **Then** the product returns the platform's answer, and the action is recorded with who asked,
   when, which process id and the platform's outcome.
4. **Given** an operator the platform refuses, **When** they send any process action, **Then** the
   platform's status and status object are returned verbatim.
5. **Given** the process id of the product's own request-handling process or of a system process
   the platform protects, **When** terminate is requested, **Then** whatever the platform answers is
   returned as it said it; the product does not keep its own list of protected processes.

---

### Edge Cases

- **A platform read returns an empty list** (no web sessions, no x509-like rows): the area is *ok*
  with a zero headline, never a failure.
- **A platform read answers 200 with an error in its status object**: treated as a failure of that
  area, with the platform's words verbatim.
- **A field the product expects is missing or has a different type** (spec 001 found read/write type
  asymmetry in WQM): the row keeps what the platform sent; the missing value is shown as absent, not
  as zero; the area does not fail for one odd row.
- **Very large readings** (thousands of processes or locks): the reading returns all rows; the
  summary headline is computed from the full read, not from a truncated one.
- **The access token expires between two reads of the summary** (60 s tokens): the affected areas
  report the platform's 401 verbatim; the product does not renew the token itself for this call.
- **Two areas share a platform read** (activity uses the dashboard read the alerts check also uses):
  each area reports its own outcome from that one read.
- **A reading or report is requested for a target server**: refused in this version with a reason
  saying overview readings are for the primary instance only.
- **Process ids are reused by the operating system**: a terminate confirmation matches the typed
  process id only; the product does not claim to know it is still the same process.

## Requirements *(mandatory)*

### Functional Requirements

**Closed set of readings**

- **FR-001**: The product MUST offer a fixed, documented list of instance readings: *processes*,
  *locks*, *memory*, *activity*, *devices*, *licenses*, *web-sessions*. Each maps to fixed platform
  reads declared in the codebase and changed only through a reviewed change.
- **FR-002**: No platform path, query string, field name or method MAY be taken from the request. A
  reading name outside the list MUST be refused as unknown without any platform call. The product
  MUST NOT offer a generic pass-through to the management API.
- **FR-003**: Each reading MUST be read at request time with the requesting operator's own
  credential. Neither the platform's data nor any permission outcome MAY be cached or stored.
- **FR-004**: Each reading MUST return its rows in a stable, documented shape with the time it was
  taken. Values the product computes MUST be limited to arithmetic over the platform's own numbers in
  the same answer (for example used share of shared memory), and MUST be labelled as computed.
- **FR-005**: The product MUST NOT label any value as host CPU, host memory or console log, since the
  platform does not report them.

**Summary**

- **FR-006**: The product MUST offer one summary call returning one entry per area: the seven
  readings and the four report areas.
- **FR-007**: Each entry MUST carry its own outcome — *ok* with a headline, *refused* with the
  platform's HTTP status and status object verbatim, or *unreachable* with the transport error — and
  the time it was read. One area's failure MUST NOT fail the summary or any other entry.
- **FR-008**: The headline of each area MUST be defined in the product's documentation (what is
  counted and from which read) and computed from the full read.
- **FR-008a**: The summary MUST NOT run a report or compute findings. Each report area's headline is
  a count from a single inexpensive platform read; findings are available only through an on-demand
  report (FR-009).

**On-demand reports**

- **FR-009**: The product MUST run any catalog step type whose executor is *platform-read* on demand
  on the primary instance, and MUST refuse every other type without calling the platform.
- **FR-010**: An on-demand report MUST be produced by the same report code, finding rules and
  parameter validation as the step in a run, so the two cannot disagree.
- **FR-011**: An on-demand report MUST NOT create a run, a step run or a log entry, and MUST NOT be
  stored.
- **FR-012**: A refused or failed read MUST yield a failed report with the platform's words verbatim,
  as the step does in a run.

**From an area to a flow**

- **FR-013**: The product MUST map each area to at most one catalog step type, in a fixed documented
  table; areas without one MUST say so when asked to become a flow. This feature MUST NOT add,
  change or remove any step-type catalog entry.
- **FR-014**: Creating a flow from an area MUST produce an ordinary flow — one step of the mapped
  type, the supplied parameters, a default name the operator can change, a WQM category that exists
  on the instance — and MUST return the result of the shared validation gate for it.
- **FR-015**: A flow created this way MUST be subject to every existing rule for flows and schedules;
  this feature MUST NOT add any path around the validation gate.

**Safety and authorization**

- **FR-016**: Every answer MUST exclude passwords, password hashes, tokens and secret values, even
  if the platform returns such a field in a reading.
- **FR-017**: Every request MUST pass the product's existing token check; there is no unauthenticated
  access to any reading, summary, report or action.
- **FR-018**: Overview readings, summaries and on-demand reports MUST refuse a target server in this
  version, with a reason naming the limitation.

**Process actions (P3, gated)**

- **FR-019**: Before any process action is offered, a spike MUST exercise suspend, resume and
  terminate against a disposable process on the dev stack and record, in this feature's `evidence/`,
  the request shape, response, state change on re-read, refusal for an unprivileged operator and any
  deviation from the published description — in the style of spec 001, with no credentials. The
  spike is User Story 5's first task, and no task of User Stories 1–4 may depend on it.
- **FR-020**: If the spike shows a usable contract, the product MUST offer suspend, resume and
  terminate by process id, with the platform's answer returned verbatim.
- **FR-021**: Terminate MUST require a typed confirmation equal to the process id and MUST answer
  with the same "confirmation required" status the destructive step uses at dispatch when it is
  missing or different, without calling the platform.
- **FR-022**: Each process action MUST be recorded with the operator, time, process id, action and
  the platform's outcome verbatim in the product's own action record, and that record MUST be
  readable through the product's API, newest first. It MUST NOT be a run, step run or run log entry,
  MUST NOT be used to decide whether a later action is allowed, and MUST be written whether the
  platform accepted or refused the action (a request refused for missing confirmation, which never
  reaches the platform, is not recorded).
- **FR-023**: If the spike shows the contract is not usable, FR-020 to FR-022 MUST NOT be built, and
  `docs/limitations.md` MUST say which action is missing and what the spike observed.

**Documentation**

- **FR-024**: `README.md`'s API reference and `docs/limitations.md` MUST describe the readings, their
  headlines, the area-to-step-type table, the primary-only rule, the absence of host CPU and console
  log, and — if built — the process actions.

### Key Entities

- **Reading**: a named, fixed view of one instance resource area; attributes: name, the platform
  reads it is made from, row shape, time read, outcome.
- **Area summary entry**: one area's headline for the overview; attributes: area, outcome (*ok*,
  *refused*, *unreachable*), headline values, platform answer when not *ok*, time read.
- **On-demand report**: a spec 013 report produced outside a run; same attributes as a step's stored
  report (summary, rows, findings with severity and item), never persisted.
- **Area-to-step mapping**: the fixed table from area to at most one catalog step type.
- **Process action record** (P3): operator, time, process id, action (suspend, resume, terminate),
  the platform's HTTP status and status object verbatim. Persisted by the product, append-only,
  independent of runs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the dev stack, each of the seven readings answers in under 2 seconds and matches the
  platform's own read taken at the same moment in row count (±5% for processes and locks, which
  change between the two reads).
- **SC-002**: The summary answers in under 3 seconds on the dev stack with all eleven areas, and an
  operator can tell which areas are healthy, refused or unreachable from that one answer alone.
- **SC-003**: For an operator whose role grants no security administration (the public demo's
  `SentaiDemo` role, spec 011), 100% of summary entries and on-demand reports whose platform read is
  refused carry the platform's refusal verbatim, 100% of entries whose read is allowed are *ok*, and
  at least the `security` entry is refused. Which other areas that role may read is recorded as
  observed, not assumed.
- **SC-004**: For each of the four report types, the on-demand report and the report stored by a
  one-step run on the same instance have the same findings (same rule, severity and item) whenever the
  stored result was not truncated to fit the run record, and the on-demand calls add 0 runs.
- **SC-005**: 0 requests outside the declared reading list reach the platform, shown by a test that
  sends unknown names, platform paths and path-traversal strings.
- **SC-006**: In a scan of every answer produced by this feature in the test suite, 0 passwords,
  password hashes, tokens or secret values appear.
- **SC-007**: A flow created from the *secrets* area is scheduled and its scheduled run produces the
  secrets inventory report, with no manual edit of the flow.
- **SC-008**: Either the process-action spike evidence is in `evidence/` and terminate is refused
  100% of the time without a matching typed process id, or the limitation is documented and no
  process action is exposed.
- **SC-009**: The existing unit suite stays green, with the new behaviour covered by tests written
  first.

## Assumptions

- Operators are the same audience as specs 007–015 and authenticate the same way; the platform
  decides every permission, so no new role or privilege is introduced by the product.
- The overview is for the primary instance in this version; readings on target servers are a later
  feature, since the remote read path of spec 008 carries its own timeout and credential rules.
- "Activity" combines the platform's system-usage and main dashboard reads; resource contention
  (seize counters) is included in *activity* rather than being its own area, to keep the list at
  seven readings.
- Disk and database coverage stays with the existing steps (`storage-headroom-check`,
  `db-size-report`) and spec 010's example flow; they are not overview areas and are not duplicated
  as readings. The area-to-step table therefore maps exactly the four report areas.
- Log-like reads (audit records, task history, journal records), x509, SSL, OAuth, roles and
  resources are separate future features; audit records is an asynchronous platform job (probed:
  202), which needs its own design.
- Headline values are counts and shares over one read at one moment; no history is kept, so no trend
  or chart over time is promised.
- The four report step types, their parameter schemas and finding rules are those merged in spec 013
  and are not changed by this feature.
