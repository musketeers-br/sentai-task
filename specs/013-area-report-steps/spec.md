# Feature Specification: Area Report Steps — Security, Web Applications, System Alerts and Secrets as Flow Steps

**Feature Branch**: `013-area-report-steps`

**Created**: 2026-09-28

**Status**: Merged

**Status note**: PR #20. 21/21 tasks; full regression record in evidence/. The four report-step catalog descriptions were written during the master merge and should be reviewed by the step authors.

**Input**: Competitor analysis (2026-09-28): the contest asks for coverage of six management areas.
SentaiTask covers task management and the Work Queue Manager in depth, but touches *security*,
*web applications / REST*, *logs* and *secrets* only indirectly. The rival portals cover them as
pages that list things. The team chose (clarification Q2) four read-only step types, so these
areas become part of the orchestration instead of more pages: **security posture report**,
**web application inventory**, **system alerts check** and **secrets inventory**. IRIS 2026.2's
management API already exposes each of these areas (probed 2026-09-28), so the steps read them
through the platform with the operator's credential, and they can run on target servers too.

## Context and Problem

An operator who wants a nightly "is this instance healthy and safe?" routine today combines
SentaiTask for integrity and storage with manual visits to the platform's portal for users,
services, web applications, alerts and wallet secrets, instance by instance. Those checks are
exactly the kind of routine a flow should carry: they can run in parallel, gate what comes next,
and run on every server of an estate.

## Objective

An operator can put a security posture report, a web application inventory, a system alerts check
and a secrets inventory on the canvas, next to integrity and storage steps, on the primary or on
any target server. Each produces a readable report with explicit findings. Each can be made to
fail on findings, so a flow can stop, or warn, when an instance drifts. The platform decides what
the operator may read; its refusal is shown as it gave it.

## Clarifications

### Session 2026-09-28

- Q: Which step types? → A: All four: `security-posture-report`, `web-app-inventory`,
  `system-alerts-check`, `secrets-inventory` (clarification Q2 of the contest plan).
- Q: Do they read the platform directly or through its management API? → A: Through the management
  API, with the run's credential for the instance the step runs on. The platform authorizes each
  read, and the same steps work on target servers (spec 008) without SentaiTask installed there.
- Q: Can a report fail the step? → A: Reports always complete when the reads succeed, unless the
  step is configured to fail on findings. `system-alerts-check` is a check: it fails when a
  configured threshold is exceeded, and its thresholds default to the strictest reasonable values.
  A refused or failed read always fails the step, with the platform's reason verbatim.
- Q: Does the secrets inventory ever read a secret's value? → A: Never. It lists collections and
  the names and types of the secrets in them, which the management API returns without values.
  If the platform ever returned a value field, the step drops it before storing anything.
- Q: What counts as a finding? → A: Fixed, documented rules per type (see Requirements), not
  configurable expressions (Constitution II). A report lists findings with a severity (*high*,
  *medium*, *info*) and the item it concerns.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Security posture report on any instance (Priority: P1)

An operator adds **Security posture report** to a flow, optionally on a target server, and runs
it. The step's result lists the enabled accounts that hold the all-powerful role, the enabled
services that accept unauthenticated connections, and whether auditing is on, each as a finding
with a severity. The operator can tick *Fail on findings* to make the step fail when any *high*
finding exists.

**Why this priority**: Security is the largest area missing from the product's coverage, and the
most valued by administrators. It is also the one where the platform's own authorization matters
most.

**Independent Test**: Run a flow with one security posture report on the primary as a fully
privileged operator: the step completes and its result lists the accounts that hold the
all-powerful role on the instance. Run it as an operator without security administration
privileges: the step fails with the platform's refusal verbatim.

**Acceptance Scenarios**:

1. **Given** an operator with the platform privilege to read security settings, **When** the step
   runs, **Then** it completes with a report listing: enabled accounts and their roles; accounts
   holding the all-powerful role (finding, *high*); enabled services accepting unauthenticated
   connections (finding, *medium*); whether auditing is enabled (finding, *high*, when it is
   off).
2. **Given** *Fail on findings* is ticked and at least one *high* finding exists, **Then** the
   step fails with a reason that counts the findings, and the report is still stored.
3. **Given** an operator the platform refuses, **Then** the step fails with the platform's reason
   verbatim, and no partial report is presented as complete.
4. **Given** the step is set to run on a target server, **Then** it reads that server's settings
   with the operator's credential for it, and the run view says where it ran.
5. **Given** the report, **Then** it never contains a password, password hash or any credential.

---

### User Story 2 - Web application inventory (Priority: P2)

An operator adds **Web application inventory** and gets the instance's web applications: path,
namespace, enabled, whether it is a REST endpoint (it names a dispatch class), the resource that
protects it and its authentication methods. Enabled, non-system applications that accept
unauthenticated access without a protecting resource are findings.

**Why this priority**: It covers the *web applications / REST* area with facts an administrator
reviews before exposing an instance.

**Independent Test**: Run the step on the dev instance: the report lists `/csp/sentai/api/v1` as a
REST endpoint that requires a password, and lists the public canvas application `/csp/sentai` as
accepting unauthenticated access.

**Acceptance Scenarios**:

1. **Given** the step runs, **Then** the report lists every web application the platform returns,
   with path, namespace, enabled, REST (dispatch class present), resource, authentication methods
   and whether it is a system application.
2. **Given** an enabled, non-system application accepting unauthenticated access with no resource,
   **Then** it is a finding: *high* when it is a REST endpoint, *medium* otherwise.
3. **Given** *Fail on findings* is ticked and a *high* finding exists, **Then** the step fails, and
   the report is still stored.
4. **Given** the platform refuses the read, **Then** the step fails with the reason verbatim.

---

### User Story 3 - System alerts check as a gate (Priority: P2)

An operator puts **System alerts check** at the head of a nightly flow, with a join after it. The
check reads the platform's dashboard: serious alerts, application errors, the status of system
resources (database space, journal space, lock table, write daemon) and license use. When a
threshold is exceeded the step fails, and the join keeps the maintenance behind it from starting.

**Why this priority**: It turns the *logs/monitoring* area into orchestration: "don't run heavy
maintenance on an instance that is already in trouble". It depends only on reads every operator
with monitoring access has.

**Independent Test**: With a clean instance (no serious alerts), the check completes. After an
alert is raised (for example by cancelling a running integrity check, which IRIS records as a
serious alert), the check fails with a reason that says how many serious alerts exist against the
threshold, and a step behind a join is not started.

**Acceptance Scenarios**:

1. **Given** the step runs, **Then** its report includes serious alerts, application errors, each
   system resource status as the platform names it, license use and limit, and the instance's
   uptime.
2. **Given** serious alerts exceed *Max serious alerts* (default 0), or application errors exceed
   *Max application errors* (default 0), or any system resource status is not the platform's
   normal status while *Require normal system status* is on (default on), **Then** the step fails
   with a reason naming each exceeded threshold.
3. **Given** all thresholds are met, **Then** the step completes.
4. **Given** the step runs on a target server, **Then** it reads that server's dashboard.

---

### User Story 4 - Secrets inventory, never values (Priority: P3)

An operator adds **Secrets inventory** and gets the platform wallet's collections and, for each,
the names and types of its secrets, without any value. A collection with no protecting resource is
a finding.

**Why this priority**: It covers the *secrets* area with a safe, useful fact sheet, and prepares
the ground for spec 015, which keeps the scheduled-run credential in the same wallet.

**Independent Test**: Create a wallet collection with one secret on the dev instance; run the step:
the report lists the collection and the secret's name and type; searching the stored result for
the secret's value finds nothing.

**Acceptance Scenarios**:

1. **Given** the step runs, **Then** the report lists each collection (name, resources that protect
   use and edit) and each secret in it (name, type), and never a value.
2. **Given** a collection without a use resource, **Then** it is a finding (*medium*).
3. **Given** the wallet is empty, **Then** the step completes with an empty inventory.
4. **Given** the platform returns a value field in any answer, **Then** the step discards it
   before storing or showing anything.

---

### User Story 5 - The steps are first-class on the canvas (Priority: P2)

The four types appear in the palette under their own groups (*Security*, *Monitoring*), with
parameter forms generated from their declared schemas. They validate, run, time out, cancel,
re-run and show results like every other step. Their results render readably in the run view: the
findings first, then the details.

**Why this priority**: Without it the steps exist only through the API, and voters judge the
canvas.

**Independent Test**: Drag each type onto the canvas, set *Fail on findings* on one, validate with
no errors, run, and open each result: findings are listed at the top with their severity.

**Acceptance Scenarios**:

1. **Given** the palette, **Then** the four types are listed with their labels in their groups, and
   are marked remote-capable (they may choose *Run on*).
2. **Given** a step of these types, **Then** the inspector shows its declared parameters with
   defaults, and validation refuses wrong types or out-of-range values on their field.
3. **Given** a finished step of these types, **Then** its result shows a findings summary
   (counts by severity) and the findings list before the full report.
4. **Given** a finished step of any other type that stored a result (for example the database size
   report), **Then** the operator can open it from the run view too; today no result is shown
   anywhere in the canvas.
5. **Given** a flow with these steps, **When** it is scheduled (spec 015) or dispatched manually,
   **Then** they behave like other non-destructive steps.

### Edge Cases

- An instance with hundreds of users or applications: the report is bounded by the step result
  size (spec 005) and says how many items were left out; findings are kept before details, so
  they are never the part cut.
- The platform lists an account but refuses to read its roles: that account appears with
  "roles not readable: <reason>" and the step is marked partial (it completes, with a *medium*
  finding "incomplete read"), unless every read failed.
- A target server runs an older IRIS whose management API lacks an endpoint: the step fails with
  the platform's answer (for example 404) verbatim; validation does not guess versions.
- The dashboard reports a status the step does not know: it is shown as reported and counts as not
  normal.
- A run is cancelled while a report step reads: reads are short, so the step ends as cancelled and
  its late result is discarded, like in-process steps today.
- The report of one of these steps is used as a gate behind a join: only the step's state matters
  to the join (as today); the report is information.

## Requirements *(mandatory)*

### Functional Requirements

**Common to the four types**

- **FR-001**: The step-type registry MUST declare `security-posture-report`,
  `web-app-inventory`, `system-alerts-check` and `secrets-inventory` as available,
  non-destructive, non-pausable and remote-capable, with their parameter schemas.
- **FR-002**: Each type MUST obtain its facts only by reading the instance's management API, with
  the run's credential for the instance the step runs on (local or target). No type may change
  anything on the instance.
- **FR-003**: A refused or failed read MUST fail the step with the platform's answer verbatim,
  except the per-item partial case of the edge cases, which is reported as a finding.
- **FR-004**: Each report MUST be stored as the step's result as structured data with a `findings`
  list (severity, rule, item, detail) placed before the details, and a `summary` with counts by
  severity; it MUST respect the step result size limit and say what was left out.
- **FR-005**: Reports MUST NOT contain passwords, password hashes, tokens or secret values. Any
  such field returned by the platform MUST be dropped before storage.
- **FR-006**: Finding rules MUST be fixed in the product, documented, and not configurable by
  expressions; parameters may only switch documented behaviours or set numeric thresholds.

**Per type**

- **FR-007** (`security-posture-report`): The report MUST list enabled accounts with their roles;
  MUST raise *high* findings for enabled accounts holding the all-powerful role and for auditing
  switched off, and *medium* findings for enabled services accepting unauthenticated connections.
  Parameter *Fail on findings* (boolean, default false) fails the step when a *high* finding
  exists.
- **FR-008** (`web-app-inventory`): The report MUST list every web application with path,
  namespace, enabled, REST (dispatch class present), resource, authentication methods and system
  flag; MUST raise a finding for each enabled, non-system application accepting unauthenticated
  access with no resource (*high* if REST, *medium* otherwise). Parameter *Fail on findings* as in
  FR-007.
- **FR-009** (`system-alerts-check`): The report MUST include serious alerts, application errors,
  each system resource status, license use and limit, and uptime. The step MUST fail when serious
  alerts exceed *Max serious alerts* (integer ≥ 0, default 0), application errors exceed *Max
  application errors* (integer ≥ 0, default 0), or, with *Require normal system status* (boolean,
  default true), any resource status is not normal; the reason names every exceeded threshold.
- **FR-010** (`secrets-inventory`): The report MUST list wallet collections with their use and edit
  resources and, per collection, secret names and types; MUST raise a *medium* finding for a
  collection with no use resource. It MUST NEVER request or store a secret's value.

**Canvas**

- **FR-011**: The palette MUST show the four types in groups *Security*
  (`security-posture-report`, `web-app-inventory`, `secrets-inventory`) and *Monitoring*
  (`system-alerts-check`), with forms generated from their schemas (spec 007 Part B).
- **FR-012**: The run view MUST let the operator open the result of any finished step that has
  one (today results are returned by the API but shown nowhere in the canvas, including the spec
  005 reports). For the four types of this spec it MUST show the findings summary and list first,
  then the details, readable without opening raw JSON; other results are shown as a readable
  tree.
- **FR-013**: The README's contest-area table MUST be updated to cite these steps for the areas
  they cover, when this feature is merged.

### Key Entities

- **Report step type**: a registry entry whose execution is a fixed set of reads on the management
  API and a fixed rule set; declares parameters, category and that it is remote-capable.
- **Finding**: severity (*high*, *medium*, *info*), rule identifier, item (account, service,
  application, collection, metric), detail.
- **Report**: `summary` (counts by severity, items read, items omitted), `findings`, then the
  type's details.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Each of the four types completes on the dev instance for a fully privileged operator
  in under 10 seconds.
- **SC-002**: A flow of the four types running in parallel on the primary and on `iris-target` (8
  steps) completes and shows, per step, where it ran and its findings.
- **SC-003**: For an operator without the needed platform privilege, 100% of these steps fail with
  the platform's refusal verbatim, and 0 present a partial report as complete.
- **SC-004**: In a scan of every stored result produced by these steps in the test suite, 0
  passwords, password hashes, tokens or secret values are found.
- **SC-005**: A nightly flow "system alerts check → join → integrity checks" does not start the
  integrity checks when the instance has a serious alert, in 100% of test runs.
- **SC-006**: The README's contest-area table lists a concrete, merged capability for each of the
  six areas.

## Assumptions

- The management API of IRIS 2026.2 exposes the reads needed (users and a user's roles, services,
  audit enabled flag, web applications, the main monitoring dashboard, wallet collections and a
  collection's secrets), as probed on 2026-09-28; the Plan records each call and answer shape.
- The operator's platform privileges decide what each step can read; the product documents which
  privileges each type needs as observed, without enforcing them.
- The step result size limit of spec 005 applies.
- Rules are deliberately few; a richer, configurable policy engine is out of scope.
- Destructive or corrective actions (disabling an account, closing a service) are out of scope; the
  steps only report.
