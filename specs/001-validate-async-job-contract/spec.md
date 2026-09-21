# Feature Specification: validate-async-job-contract

**Feature Branch**: `001-validate-async-job-contract`

**Created**: 2026-09-20

**Status**: Draft

**Input**: User description: "Spike to answer six technical questions about
the target data platform's management API before any dependent feature is
designed. Deliverable is committed evidence and a recorded execution-model
decision."

## Overview

This feature is a **spike**, not a product feature. It ships no user-facing
behavior. Its output is a set of committed artifacts — response samples, a
compatibility statement, and a recorded decision — that every subsequent
feature will consume as its interface contract with the target data platform's
management API.

The "user" of this deliverable is the engineer designing any downstream
feature. That reader must be able to answer each of the six questions below,
and to reconstruct the platform's response shapes, from the committed
artifacts alone — without re-running the spike, and without conversation with
the person who did.

Nothing else may be specified or built until this spike closes with a
recorded decision.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Downstream engineer reaches the platform and reads the auth contract (Priority: P1)

A downstream feature designer opens the committed evidence and, from it
alone, learns how to reach the management API on the platform's freely
available edition, what a successful authentication response looks like
field-for-field, and how a session is renewed. They can go on to design their
own feature against that contract without contacting the person who ran the
spike.

**Why this priority**: Every other question in this spike, and every
downstream feature, depends on being able to reach an authenticated session.
If this question does not close, none of the others can be answered.

**Independent Test**: A reader who did not run the spike opens the committed
artifacts, reads a captured successful-authentication response, identifies
the fields that hold the session identity and the session's renewal
mechanism, and confirms the compatibility statement records the answer to
question 1 with the evidence file it is drawn from.

**Acceptance Scenarios**:

1. **Given** the committed artifacts, **When** the reader looks for evidence
   that the management API responds on the platform's freely available
   edition, **Then** they find a captured successful response whose file
   names the platform version it came from.
2. **Given** the committed artifacts, **When** the reader looks for the
   authentication response envelope, **Then** they find a captured sample
   showing every field, its type, and its nesting, plus a compatibility-
   statement entry naming which fields carry session identity.
3. **Given** the committed artifacts, **When** the reader looks for how a
   session is renewed, **Then** the compatibility statement records the
   mechanism and points to the evidence that demonstrates it.

---

### User Story 2 - Downstream engineer confirms the async job contract and reads the execution-model decision (Priority: P1)

A downstream feature designer opens the committed evidence to learn whether
heavy maintenance operations return a job identifier for later observation,
whether that identifier can be used to read execution state, failure reason,
and timings, and whether a running job can be cancelled, paused, and resumed.
They then read the recorded execution-model decision and know, without
ambiguity, whether parallel execution is delegated to the platform or must
be built inside the product.

**Why this priority**: Questions 3 and 4 together are the decision gate. A
positive close on both keeps the planned scope; a negative close on either
requires building the execution engine inside the product and reducing scope
the same day. Until this closes, no dependent feature can be designed.

**Independent Test**: A reader who did not run the spike opens the committed
artifacts, reads the captured accepted-for-processing response and the
captured status-resource responses across a job's lifecycle, and confirms the
recorded decision matches the evidence and states its consequence explicitly.

**Acceptance Scenarios**:

1. **Given** the committed artifacts, **When** the reader inspects a heavy
   maintenance operation's captured response, **Then** they find either an
   accepted-for-processing response carrying a job identifier, or a captured
   synchronous response, and the compatibility statement names which of the
   two the platform actually did.
2. **Given** a captured job identifier and the committed evidence, **When**
   the reader inspects the captured status-resource responses, **Then** they
   find recorded samples covering execution state, failure reason (from a
   deliberately failed job), and queued/started/finished timings — or a
   compatibility-statement entry stating exactly which of these the platform
   does not expose.
3. **Given** the committed artifacts, **When** the reader looks for cancel,
   pause, and resume transitions, **Then** they find a captured response for
   each supported transition, and the compatibility statement records which
   transitions the platform does not support.
4. **Given** the committed artifacts, **When** the reader reads the
   execution-model decision, **Then** they find both the decision itself
   (delegate to platform / build inside product) and the consequence it
   triggers, with a citation back to the evidence for questions 3 and 4.

---

### User Story 3 - Downstream engineer reads the actual response shapes for scheduled tasks (Priority: P2)

A downstream feature designer needs the real JSON returned when listing
scheduled tasks, reading a single task, and reading a task's
non-configurable information. From the committed evidence they learn the
field names, types, nesting, and — critically — whether the identifiers
needed by other operations are present in those responses at all.

**Why this priority**: The published contract omits response schemas, so the
committed samples are the contract downstream features consume. Design of
any scheduled-task feature is blocked until this closes.

**Independent Test**: A reader who did not run the spike opens the committed
artifacts, finds one captured response for each of the three reads, and
confirms the compatibility statement lists — per response — which identifier
fields are present and which are absent.

**Acceptance Scenarios**:

1. **Given** the committed artifacts, **When** the reader opens the sample
   for the list endpoint, **Then** they see the full JSON returned, including
   the top-level envelope.
2. **Given** the committed artifacts, **When** the reader opens the sample
   for reading a single task, **Then** they see the full JSON returned,
   including any nested objects and their fields.
3. **Given** the committed artifacts, **When** the reader looks for the
   task's non-configurable information, **Then** they see a separate captured
   sample and a compatibility-statement entry noting which fields it uniquely
   carries.
4. **Given** the committed evidence, **When** the reader asks whether
   identifiers needed by other operations are present, **Then** the
   compatibility statement answers explicitly per identifier — present,
   absent, or renamed — with a pointer to the field in the evidence.

---

### User Story 4 - Downstream engineer confirms worker-capacity categories are readable and writable (Priority: P3)

A downstream feature designer needs to know whether the platform exposes its
worker-capacity categories through the management API, whether they can be
read, and whether writing one takes effect and reads back changed. From the
committed evidence they confirm the round-trip works, or they read the
compatibility statement's explanation of why it does not.

**Why this priority**: Downstream features that adjust ceilings depend on
this answer, but design work on the core flow model does not. This question
can close after the decision gate.

**Independent Test**: A reader who did not run the spike opens the committed
artifacts and finds three captured responses: a read of the current
worker-capacity categories, a write that modifies one, and a second read
showing the modified value.

**Acceptance Scenarios**:

1. **Given** the committed artifacts, **When** the reader looks for a read
   of the worker-capacity categories, **Then** they find one captured
   response showing the full JSON.
2. **Given** the committed artifacts, **When** the reader looks for a write
   that modifies a category, **Then** they find one captured request and
   response, and a compatibility-statement entry naming the category modified
   and the value written.
3. **Given** the committed artifacts, **When** the reader looks for a
   subsequent read, **Then** they find a captured response whose modified
   value matches what was written — or a compatibility-statement entry
   recording that the write did not persist and why.

---

### User Story 5 - Downstream engineer learns whether the task-chaining predecessor identifier is obtainable (Priority: P3)

A downstream feature designer opens the committed evidence to determine
whether the identifier of a scheduled task's predecessor — the task it is
configured to run after — is obtainable from the management API at all.
From that single answer they know whether a task-chain visualization feature
can be built.

**Why this priority**: This answer decides feasibility of one specific
downstream feature. It does not block the core spike decision, and design of
that dependent feature is blocked until it closes.

**Independent Test**: A reader who did not run the spike opens the committed
artifacts and finds either a captured response in which the predecessor
identifier appears, or a compatibility-statement entry stating explicitly
that no endpoint exposes it and listing every read that was attempted.

**Acceptance Scenarios**:

1. **Given** the committed artifacts, **When** the reader looks for the
   predecessor identifier, **Then** they find either a captured response
   field that carries it or a compatibility-statement entry stating it is
   not obtainable.
2. **Given** the compatibility statement records that it is not obtainable,
   **When** the reader inspects the entry, **Then** it lists the reads
   attempted and the fields inspected, so a future spike need not retrace
   the same steps.

---

### Edge Cases

- A read returns something other than JSON (HTML error page, empty body,
  redirect). The evidence MUST capture the actual response as returned, and
  the compatibility statement MUST record the deviation from the published
  contract.
- A response envelope differs from the published contract (extra fields,
  renamed fields, missing fields). The compatibility statement MUST record
  every deviation observed.
- A transition the description assumes exists (pause, resume) is not
  supported by the platform. This is a valid recorded answer, not a spike
  failure; the compatibility statement MUST state which transitions are
  unsupported.
- A question cannot be closed within the spike's window. It MUST be recorded
  as an open risk, naming the dependent feature it blocks, rather than left
  silent or reported as closed.
- The platform is reachable but authentication cannot be established. This
  closes question 1 negatively; the spike stops and the compatibility
  statement records the blocker as an open risk for every downstream feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The spike MUST commit, into the feature directory, one
  captured request/response artifact per endpoint exercised. Each artifact
  MUST include the full response body as returned by the platform, the
  status code, and the response headers relevant to interpretation of the
  body.
- **FR-002**: The spike MUST commit a compatibility statement that names the
  exact platform version exercised (product name, edition, and version
  identifier as reported by the platform itself, not by the operator).
- **FR-003**: The compatibility statement MUST answer each of the six
  questions with: the answer, a pointer to the evidence artifact supporting
  it, and a note of any deviation from the published contract.
- **FR-004**: The compatibility statement MUST record, for question 4, which
  job-observation and control transitions the platform supports and which it
  does not, with an evidence pointer for each supported transition and an
  explicit "not supported" entry for each unsupported one.
- **FR-005**: The spike MUST record an execution-model decision naming one
  of two outcomes: "delegate parallel execution to the platform" or "build
  execution engine inside the product". The decision MUST cite the evidence
  for questions 3 and 4 that supports it.
- **FR-006**: The recorded decision MUST state its consequence explicitly:
  if the decision is "build inside the product", the compatibility statement
  MUST also record that the planned scope of dependent features is to be
  reduced, and MUST name the reduction as a follow-up action, so the
  negative outcome produces a decision rather than a retry.
- **FR-007**: Any of the six questions that could not be closed MUST be
  recorded in the compatibility statement as an open risk, naming the
  dependent feature or features it blocks. It MUST NOT be omitted or
  reported as closed.
- **FR-008**: The committed artifacts MUST be self-contained: a reader who
  did not run the spike MUST be able to reconstruct each of the six answers
  from the artifacts alone, without contacting the operator and without
  re-running any probe.
- **FR-009**: Every captured request MUST have its authentication and
  identifying details redacted before commit, so the artifacts are safe to
  ship in the repository. Redaction MUST NOT alter response body structure
  in a way that changes field names, types, or nesting.
- **FR-010**: The spike MUST NOT produce any user interface, any product
  feature, or any persisted state beyond the captured evidence. It MUST NOT
  design the flow model, the step library, or any downstream feature.

### Key Entities

- **Evidence Artifact**: A committed file (or small set of files) recording
  one platform interaction. Carries the request that was sent (redacted),
  the response body as returned, the status code, and enough context — a
  named endpoint, a timestamp, the platform version — for a reader to place
  it in the answered question.
- **Compatibility Statement**: A committed prose document that names the
  platform version exercised, answers each of the six questions with an
  evidence pointer, and records every deviation from the published
  contract.
- **Execution-Model Decision**: A committed statement of which of the two
  outcomes was reached ("delegate to platform" or "build inside product"),
  the evidence that supports it, and the consequence it triggers.
- **Open Risk**: A recorded entry, in the compatibility statement, for any
  question that could not be closed. Names the question, the reason it
  could not be closed, and the dependent feature or features that are
  blocked as a result.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every one of the six questions has a recorded answer in the
  compatibility statement, each with a pointer to at least one committed
  evidence artifact.
- **SC-002**: The exact platform version exercised is named in the
  compatibility statement, in a form drawn from the platform's own reply
  rather than from the operator's recollection.
- **SC-003**: A reader who did not run the spike can, from the committed
  artifacts alone, reconstruct each of the six answers and identify every
  field name and nesting relationship in the recorded response shapes.
- **SC-004**: The execution-model decision is recorded with its rationale
  and its consequence, and a reader can determine from the recorded
  decision alone whether the planned scope of dependent features stands or
  is reduced.
- **SC-005**: Every question that could not be closed is present in the
  compatibility statement as an open risk, naming the dependent feature it
  blocks. Zero questions are silently omitted.
- **SC-006**: Zero evidence artifacts contain the operator's credentials or
  session tokens in un-redacted form.

## Assumptions

- **Target platform**: The spike exercises InterSystems IRIS, Community
  Edition, run as a container image. The compatibility statement records
  the exact version reported by the running instance and the image's
  SHA256 digest.
- **Published contract**: The platform's published contract documents
  request bodies in full; the spike does not need to discover request
  shapes, only response shapes and behavior. Request bodies are used
  as documented.
- **Evidence-as-contract**: The evidence artifacts committed by this spike
  become the interface contract every downstream feature consumes. They
  are not throwaway; changes to them are treated as contract changes.
- **Free edition representativeness**: The freely available edition of the
  platform is representative enough of the licensed edition that response
  shapes and job semantics observed on the free edition will also apply to
  licensed deployments; any deviation discovered later is a separate spike.
- **Evidence layout**: Evidence artifacts and the compatibility statement
  live under this feature's directory. One evidence file per platform
  interaction, stored under `evidence/` with an ordering-preserving name
  drawn from the call sequence in the plan. The compatibility statement
  and the execution-model decision live at the feature directory root.
  The Plan documents the exact filenames and the internal shape of each
  artifact.
- **Public repository**: The repository is public. Every committed artifact
  MUST have credentials, bearer tokens, refresh tokens, and any other
  session-identity value redacted before it is written to disk.
- **Plan-level choices**: The Plan decides how probes are executed (client,
  runner, serialization format). This specification does not constrain
  those choices.
