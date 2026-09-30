# Feature Specification: Security Inventory — Roles, Resources, Certificates and OAuth (read-only)

**Feature Branch**: `specs/020-security-inventory`

**Created**: 2026-09-29

**Status**: Draft

**Input**: User description: "Spec number 020 (short name: security-inventory). Security: roles, resources, SSL/x509 and OAuth, read-only, with an expiring-certificate finding as a schedulable step. The contest's Security/Permissions and Secrets areas are only partly covered today (security-posture-report and secrets-inventory from spec 013; nothing for x509 or OAuth). The platform's management API v2 has, tested live on the dev instance: roles (43), resources (136), SSL configurations (4), x509 credentials (0 on the instance), and 33 OAuth2 operations (server, clients, server definitions, resource servers) — the OAuth server answers ERROR #8864 'not configured' and client configurations require a server id. Scope: read-only inventory of roles and their resources, resources and their public permissions, SSL/TLS configurations, x509 credentials (with validity dates) and OAuth2 configuration, in the same mould as secrets-inventory (spec 013: findings first, runs locally or on a target server); a finding 'certificate expires in N days' (threshold as a step parameter) that fails the step when crossed, so a flow scheduled with spec 015 warns before a certificate expires. 'Not configured' and empty lists are legitimate empty states, and every refusal is the platform's own, passed through unchanged. Nothing is written to the platform; no secret or private key material is ever read or shown. Spec 016 is reserved for another person; 018 (Portal overview + OS resources) and 019 (platform logs) are separate specs."

## Context

Spec 013 made security visible inside flows (`security-posture-report`, `secrets-inventory`), but
two parts of the contest's Security and Secrets areas are still absent: **who may do what**
(roles and the resources they grant, and what the public may do without any role) and **the
instance's certificates and OAuth configuration**. The team's review of 2026-09-29 ("O que o
SentaiTask entrega hoje") names the strongest story for the jury: a scheduled flow that warns
*before* a certificate expires.

This spec adds three report steps in the spec 013 mould — read through the platform, findings
first, locally or on a target server, schedulable with spec 015 — and nothing else: no writes, no
new screen (the overview screen is spec 018; platform logs are spec 019).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A scheduled flow warns before a certificate expires (Priority: P1)

An operator adds *Certificate expiry check* to a flow, sets *Warn days* to 30, and schedules the
flow weekly (spec 015). Every week the step reads the instance's SSL/TLS configurations and x509
credentials through the platform. When any certificate expires within 30 days, or has already
expired, the step fails, its result lists the certificate, its expiry date and the days left, and
the flow's join keeps the next step from running — so the history shows a failed scheduled run
with the reason, weeks before the outage.

**Why this priority**: It is the one capability here that prevents an incident rather than
describing a state, and it ties three product strengths together: report steps (013), scheduling
(015) and joins. It is the story the review singled out.

**Independent Test**: With a test certificate that expires in 10 days present on the instance
(created by the test and removed after), run a flow with the step (*Warn days* 30): the step fails
and names the certificate; with *Warn days* 5, the same step completes and lists the certificate
as an informational item. Schedule the flow and let it fire (acceptance script): the scheduled run
fails with the same reason.

**Acceptance Scenarios**:

1. **Given** a certificate that expires in fewer days than *Warn days*, **When** the step runs,
   **Then** the step fails with a reason that names how many certificates cross the threshold, and
   its result lists each one first (name, where it is used, expiry date, days left) as a *high*
   finding when already expired and a *medium* finding otherwise.
2. **Given** every certificate expires later than *Warn days*, **When** the step runs, **Then** it
   completes and its result lists every certificate with its expiry date and days left.
3. **Given** the instance has no SSL/TLS configuration and no x509 credential, **When** the step
   runs, **Then** it completes with an empty report that says so ("no certificates on this
   instance"), not a failure.
4. **Given** the flow is scheduled (spec 015) and the threshold is crossed, **When** the task
   fires, **Then** the scheduled run fails with the same reason, visible in the run history.
5. **Given** the step is placed on a target server, **When** it runs, **Then** it reports that
   server's certificates, read with the operator's credential for that server.

---

### User Story 2 - See who may do what: roles, resources and public permissions (Priority: P1)

An operator runs *Permissions inventory* and gets, first, the findings: resources the public (no
role at all) may write or use, and roles that grant the all-powerful role; then every role with the
resources and permissions it grants, and every resource with its public permission.

**Why this priority**: "Permissions" is a named contest area and today only the list of users is
read. Roles and resources are the platform's own model of authorization; showing them, with the
risky combinations called out, is the core of the Security/Permissions story.

**Independent Test**: Run the step on the dev instance: the report lists all roles and resources
the platform returns (counts equal to the platform's own lists) and flags any resource with a
public write or use permission.

**Acceptance Scenarios**:

1. **Given** the instance's roles and resources, **When** the step runs, **Then** the report lists
   every role (name, description, resources with their permissions, roles it grants) and every
   resource (name, public permission), with the item counts in its summary.
2. **Given** a resource whose public permission includes write or use, **When** the step runs,
   **Then** it is a finding: *high* for a database, administration or development resource,
   *medium* otherwise.
3. **Given** a role other than the all-powerful role itself that grants it, **When** the step runs,
   **Then** it is a *high* finding.
4. **Given** *Fail on findings* is ticked and a *high* finding exists, **Then** the step fails, and
   the report is still stored.

---

### User Story 3 - OAuth configuration at a glance, including "not configured" (Priority: P2)

An operator runs *OAuth inventory* and sees whether this instance is an OAuth authorization
server, its server definitions, client configurations and resource servers — or, on an instance
where OAuth was never set up, a clear "OAuth is not configured on this instance" that completes
normally.

**Why this priority**: It completes the Secrets/Security picture for the jury, but most instances
(including the dev and demo stacks) have no OAuth configured, so its day-to-day value is lower than
certificates and permissions.

**Independent Test**: On the dev instance (OAuth not configured) the step completes with the
not-configured state and the platform's own text; with an OAuth client configuration created by
the test (and removed after), the report lists it with its findings.

**Acceptance Scenarios**:

1. **Given** OAuth is not configured, **When** the step runs, **Then** it completes, the report
   states "not configured" with the platform's own message, and no finding is raised.
2. **Given** OAuth server definitions, clients or resource servers exist, **When** the step runs,
   **Then** each is listed with its name, issuer or server it belongs to, grant types, redirect or
   endpoint addresses, and enabled state — never any client secret.
3. **Given** a client that allows the resource-owner password grant, or an endpoint or redirect
   address that is not https (except loopback), **When** the step runs, **Then** each is a
   *medium* finding.

---

### User Story 4 - The three reports read like the others (Priority: P2)

The three new types appear in the canvas palette (Security group), accept their parameters in the
inspector with field errors, validate, can be placed on target servers, can be scheduled, and open
in the run view's result panel with the findings summary and list first, like spec 013's reports.

**Why this priority**: Consistency with the existing report steps is what makes them usable
without new learning; it reuses the existing surfaces.

**Independent Test**: Drag each type onto the canvas, set its parameters, validate with no errors,
run, open each result: findings first, then the details.

**Acceptance Scenarios**:

1. **Given** the palette, **Then** the three types are in the *Security* group, available.
2. **Given** *Warn days* outside 1–365, **Then** validation reports the field error before any run.
3. **Given** a finished step of these types, **Then** its result shows the findings summary
   (counts by severity) and the findings list before the full report.

### Edge Cases

- **Refused read**: when the platform refuses a read (the operator lacks the privilege), the step
  fails with the platform's own status and message, verbatim; nothing is guessed or partially
  claimed as complete.
- **Partly refused**: when one of a step's reads is refused and another succeeds (for example
  x509 credentials readable but SSL configurations not), the report keeps what was read and adds a
  finding "incomplete read" naming the refused part with the platform's text; the step fails only
  if every read failed.
- **Validity not reported**: when the platform returns a certificate without an expiry date, the
  item is listed as "validity not reported by the platform" (*info*) and never counted as
  expiring; the product does not open certificate files to compute it.
- **Certificate used in several places**: the same certificate referenced by several SSL/TLS
  configurations is listed once per configuration, with the configuration named, so each use is
  visible; the threshold count names distinct certificates.
- **OAuth reads that need a server id**: client configurations are read per server definition; when
  there are no server definitions, there are no client configurations to read, which is not an
  error.
- **Large inventories**: reports are bounded by the existing result size limit (spec 005/013):
  findings are kept first, and the report says how many detail items were left out.
- **Clock**: "days left" is computed from the instance's current date, stated in the report.
- **Target server down**: as for any remote step (spec 008): the step fails with the transport
  error; other steps follow their joins.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The step catalog MUST add three available, non-destructive, remote-capable report
  types in the *Security* category: `permissions-inventory`, `certificate-expiry-check`,
  `oauth-inventory`.
- **FR-002**: Every read MUST go through the platform's management interface with the credential
  of the run (the operator's, or the run-as account's for a scheduled run, or the target
  credential for a remote step); the platform decides, and its refusal MUST be passed through
  unchanged as the step's failure reason (Constitution III).
- **FR-003**: The steps MUST NOT write anything to the platform, and MUST NOT read, store or show
  any secret: no private keys, key passwords, client secrets or certificate private material. Only
  names, subjects, issuers, validity dates, usage and configuration flags are kept.
- **FR-004**: Each report MUST be stored as the step's result in the spec 013 shape: a `summary`
  (counts by severity, items read, items omitted, the instance date used), `findings` (severity,
  rule, item, message), then the details.
- **FR-005**: Finding rules MUST be fixed in the product and documented; they are not
  configurable expressions (Constitution II). Only the parameters below change a step's behaviour.
- **FR-006** (`certificate-expiry-check`): MUST read SSL/TLS configurations and x509 credentials
  and list each certificate with its name or subject, where it is used, issuer, expiry date and
  days left. MUST raise a *high* finding for an expired certificate and a *medium* finding for one
  expiring within *Warn days* (integer 1–365, default 30). The step MUST fail when at least one
  certificate is expired or within *Warn days*, with a reason that counts them; otherwise it
  completes.
- **FR-007** (`permissions-inventory`): MUST list every role (name, description, resources with
  permissions, granted roles) and every resource (name, public permission). MUST raise a *high*
  finding for a public write or use permission on a database, administration or development
  resource, a *medium* finding for a public write or use permission on any other resource, and a
  *high* finding for a role other than the all-powerful role that grants it. Parameter *Fail on
  findings* (boolean, default false) fails the step when a *high* finding exists.
- **FR-008** (`oauth-inventory`): MUST report whether OAuth is configured; when the platform
  answers that it is not configured, the step MUST complete with that state and the platform's own
  message, and no finding. Otherwise it MUST list the authorization server (when this instance is
  one), server definitions, client configurations per server definition and resource servers, and
  MUST raise a *medium* finding for a client allowing the resource-owner password grant and for a
  non-https address (loopback excepted). Parameter *Fail on findings* as in FR-007.
- **FR-009**: The three types MUST be usable on target servers (spec 008) and in scheduled flows
  (spec 015); nothing in them depends on an operator being present.
- **FR-010**: The canvas MUST show the three types in the palette, their parameters in the
  inspector with field errors from validation, and their results in the run view's result panel
  with the findings summary and list first (as spec 013).
- **FR-011**: A partly refused read MUST keep what was read and add an "incomplete read" finding
  (*medium*) naming the refused part with the platform's text; the step fails on reads only when
  every read was refused.
- **FR-012**: The README MUST describe the three steps, their fixed rules and parameters, and show
  the "certificate expires in N days" scheduled-flow example; the contest-area table MUST name
  them under Security/Permissions and Secrets.

### Key Entities

- **Certificate item**: name or subject, issuer, where it is used (SSL/TLS configuration name or
  x509 credential), expiry date as the platform reports it, days left, status (*expired*,
  *expiring*, *valid*, *validity not reported*).
- **Role item**: name, description, resources with permissions, granted roles.
- **Resource item**: name, public permission.
- **OAuth item**: kind (authorization server, server definition, client configuration, resource
  server), name, server it belongs to, grant types, addresses, enabled state.
- **Finding / Report**: as in spec 013 — severity (*high*, *medium*, *info*), rule identifier,
  item, message; report = summary, findings, details.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With a certificate expiring inside the threshold, a scheduled flow containing the
  certificate check produces a failed scheduled run naming that certificate, on the first firing
  after it enters the threshold (acceptance on the real platform).
- **SC-002**: The permissions report's role and resource counts equal the platform's own lists on
  the dev instance (43 roles and 136 resources at the time of writing, or whatever the platform
  returns on the day).
- **SC-003**: On an instance without OAuth, the OAuth step completes in 100% of runs with the
  not-configured state and the platform's message — never a failed step.
- **SC-004**: No result, log entry, export or evidence file produced by these steps contains a
  private key, key password or client secret (scan of the stored results and evidence).
- **SC-005**: An operator finds the answer to "which certificates expire in the next 30 days?" in
  under one minute from an empty canvas (add the step, run, read the first lines of the result).
- **SC-006**: Each of the three steps runs on the target server of the compose stack and reports
  that server's items, not the primary's.

## Assumptions

- **Three step types, not one.** One step per question (who may do what; which certificates
  expire; how OAuth is set up) keeps each result short, lets the certificate check be the only one
  that fails by default, and lets a flow schedule just the check. To be confirmed in
  `/speckit-clarify`.
- **The platform reports validity dates.** A platform spike (the plan's T001, with a stop
  condition) confirms which fields the SSL/TLS configuration and x509 credential reads return. If
  the platform does not expose validity for a kind of item, that item is listed as "validity not
  reported" and the gap is documented as a platform deviation; the product never reads certificate
  files itself.
- **Test certificates are fixtures.** The dev instance has 0 x509 credentials; tests and the
  acceptance script create a short-lived test certificate (and an OAuth client configuration where
  possible) on the dev stack and remove them afterwards. Nothing is created on a real deployment.
- **Severity lists are fixed.** "Database, administration or development resource" means the
  platform's resource name families for databases, administration and development; the exact list
  is documented in the README and the plan.
- **Result size** follows the existing limit (spec 005/013); findings are never truncated before
  details.
- **Depends on**: spec 013 (report executor, result panel, findings shape), spec 008 (targets),
  spec 015 (scheduling). Spec 018 (overview screen) may show these reports later; that is out of
  scope here. Spec 016 is reserved for another person; 019 covers platform logs.
- **Out of scope**: any write (create, renew or delete certificates; change roles, resources or
  OAuth), notifications outside SentaiTask (e-mail, chat), and computing validity from files.
