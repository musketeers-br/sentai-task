<!--
Sync Impact Report
==================
Version change: (uninitialized template) → 1.0.0
Bump rationale: Initial ratification of the SentaiTask Constitution.

Principles established (all new):
  1. Layered Architecture
  2. Closed Capability Set
  3. Delegated Authorization
  4. Errors as Values
  5. Verifiable Increments
  6. Technology Agnosticism

Sections added:
  - Core Principles
  - Engineering Standards
  - Workflow
  - Governance

Sections removed: none (template placeholders replaced).

Templates requiring updates:
  ✅ .specify/templates/plan-template.md — "Constitution Check" gate remains
     generic ("[Gates determined based on constitution file]"); no rewrite
     required, but reviewers MUST evaluate plans against the six principles.
  ✅ .specify/templates/spec-template.md — remains generic; no changes required.
     Spec authors MUST keep specifications free of implementation-specific
     technology choices (Principle 6).
  ✅ .specify/templates/tasks-template.md — remains generic; no changes
     required. Task authors MUST slice by verifiable user-observable behavior,
     not by technical layer (Principle 5).
  ⚠ README.md and any runtime guidance docs — none currently exist that
     reference constitutional rules; revisit when introduced.

Deferred TODOs: none.
-->

# SentaiTask Constitution

SentaiTask is a visual orchestrator for scheduled administrative maintenance on
a data platform. Operators compose flows of privileged maintenance operations
on a canvas; the platform's native scheduler executes the flow, running its
steps in parallel against the platform's management API. The product is
declarative: the user designs what should happen, and the platform executes it.

This Constitution defines the engineering principles that govern how the
system is built. It is normative. It does not prescribe technology.

## Core Principles

### I. Layered Architecture

Presentation, application logic, and infrastructure MUST be separated as
distinct layers. Dependencies MUST point inward, toward the application core:
the core MUST NOT depend on presentation or on any concrete infrastructure.
Composition of concrete implementations against abstractions defined by the
core MUST occur only at the application edge, where the process is assembled.
Cross-layer shortcuts — presentation reaching into infrastructure, or the core
importing a specific delivery or persistence mechanism — MUST NOT exist.

**Rationale**: The system orchestrates privileged operations against a data
platform whose management API will evolve, and it exposes those operations
through a canvas whose form will change. Isolating the core from both edges
keeps the rules of the domain — flow composition, scheduling contracts,
capability semantics — stable while the interfaces around them are replaced or
extended. This principle names the architectural property; it deliberately
does not impose any particular pattern, container, or mechanism for achieving
it — those are Plan-level decisions.

### II. Closed Capability Set

The system MUST expose only a predeclared, enumerable set of operations, each
one identified, versioned, and documented as part of the codebase. The system
MUST NOT execute code supplied at runtime by a user, by configuration, or by
any external source, and MUST NOT construct executable code by string
composition, template evaluation, or reflective invocation of names taken from
input. New capabilities MUST be added by extending the declared set through
the ordinary change process; they MUST NOT be added by evaluating input.
Inputs to a declared capability are data, not code, and MUST be validated
against a declared schema before the capability runs.

**Rationale**: The product configures privileged work against production
systems. A capability set that can be extended at runtime — by an uploaded
snippet, a scripted node, an expression field, or a dynamically dispatched
name — turns every input surface into a remote-code-execution surface against
those systems. A closed set makes every operation the system can perform
auditable in the source tree and reviewable before it ships.

### III. Delegated Authorization

Authorization decisions MUST be made by the platform that owns the resource
being acted upon. The application MUST NOT reimplement the platform's
permission model, MUST NOT cache permission outcomes across requests, and MUST
NOT infer, predict, or grant access based on prior successes. When the
platform denies an operation, the denial — including the reason the platform
gave — MUST be surfaced to the user without modification or paraphrase that
loses information.

**Rationale**: The platform is the system of record for who may do what to
which resource, and its policy changes without notifying us. Any local copy of
that policy will drift and will, sooner or later, authorize an action the
platform would have refused. Delegating each decision at the moment of use
keeps the application's view of permission aligned with the platform's, and
preserves the platform's explanation so the operator can act on it.

### IV. Errors as Values

Predictable failures — a rejected input, a denied operation, a rule that a
step's preconditions are not met, a partial outcome from a multi-step run —
MUST be represented as explicit success-or-failure results that cross layer
boundaries as ordinary values. Exceptions MUST be confined to the
infrastructure edges where they originate; they MUST NOT be used as control
flow across the application core. A run in which some steps succeed and
others fail MUST be representable as such: partial failure MUST NOT be
reported as success, and per-step outcomes MUST be preserved in the run's
result.

**Rationale**: A scheduled flow of privileged operations either executes as
declared or it does not, and the operator needs to know which. Encoding
failure as a value makes every layer that hands off a result account for it,
prevents silent recovery from turning a broken run into a "successful" one,
and keeps the truth of partial runs — this succeeded, that was denied, this
timed out — intact all the way to the report the operator reads.

### V. Verifiable Increments

Every unit of work MUST deliver behavior that a user can observe end-to-end,
and MUST carry the automated test that demonstrates that behavior. Work MUST
NOT be divided by technical layer — no unit whose deliverable is "the model
layer for X", "the API for Y", or "the UI for Z" in isolation. When one unit
of work requires another to be complete first, the sequencing dependency MUST
be declared explicitly rather than assumed.

**Rationale**: Layer-sliced work produces tickets that close green while the
product still does nothing a user can see; a "model layer" merged without its
service, endpoint, and canvas node has delivered zero verifiable
functionality, and the integration debt collects silently until an integration
sprint. Slicing by observable behavior guarantees that every merged unit
moves the product forward in a way the operator, or the automated test that
stands in for the operator, can confirm.

### VI. Technology Agnosticism

This Constitution MUST NOT mandate a programming language, framework, library,
data store, interface architecture, state management pattern, build tool,
container runtime, packaging format, or any other specific technology.
Technology choices MUST be made in the Plan and justified against the
principles above; the Plan MAY reference the target data platform and its
management API as the problem domain, but every technology chosen to build
against them is an implementation decision that MUST stay out of this
document. A rule that would still hold if the entire stack were rewritten in
a different technology belongs here; a rule that names how something is
built does not.

**Rationale**: The Constitution is the durable contract of the project; the
Plan is the disposable one. Binding this document to today's stack turns
every routine technology change — a swap of framework, a new persistence
choice, a different container runtime — into a constitutional amendment, and
freezes decisions that the Plan is the right place to revisit. Keeping this
document technology-free lets it outlive the choices it governs.

## Engineering Standards

The project adopts the following standards. Compliance is a review gate; each
Plan MUST show how its approach satisfies them.

- **SOLID.** Design and refactor toward single responsibility, open/closed,
  Liskov substitution, interface segregation, and dependency inversion.
  Deviations MUST be justified in the Plan, not accumulated silently.
- **Clean Architecture.** Concentric layering with dependencies pointing
  inward; boundaries are crossed only through abstractions the inner layers
  own. This is the operational form of Principle I.
- **Test-Driven Development.** A failing automated test MUST exist before the
  code that makes it pass. The unit of test corresponds to the unit of
  verifiable behavior defined in Principle V, not to a technical layer.
- **Error as Value.** Predictable failures MUST cross boundaries as values,
  per Principle IV. Exceptions MUST NOT be used as control flow across the
  application core.
- **Separation of Concerns.** Each module MUST have one reason to change.
  Concerns that belong to different layers MUST NOT be co-located in the same
  module, and orthogonal concerns within a layer MUST be split.
- **YAGNI.** Do not build for hypothetical requirements. Abstractions,
  configuration surfaces, and extension points MUST be introduced when a
  concrete second use case appears, not in anticipation of one.
- **Reproducibility.** A stranger with a clean checkout MUST be able to run
  the system from a single documented command, without installing any
  toolchain of their own beyond what that command bootstraps. The command
  and its prerequisites MUST be discoverable in the repository root.

## Workflow

Every change to product behavior MUST proceed in this order:

1. **Constitution** — read; any conflict with it blocks the work until the
   Constitution is amended or the work is redesigned.
2. **Spec** — describe the change in terms of user-observable behavior, free
   of implementation choices.
3. **Plan** — resolve the technology decisions the Spec deliberately omits,
   justified against the principles.
4. **Tasks** — decompose into verifiable increments per Principle V, with
   dependencies made explicit.
5. **Implementation** — build task by task, following TDD.
6. **Tests** — automated tests MUST exist before merge and MUST cover the
   observable behavior each task delivers.
7. **Review** — the diff MUST be reviewed against this Constitution, the
   Spec, the Plan, and the tests before it ships.

## Governance

This Constitution supersedes ad-hoc practice. Amendments follow semantic
versioning:

- **MAJOR**: A principle is removed, or its meaning is redefined
  incompatibly.
- **MINOR**: A new principle is added, or an existing principle is
  materially expanded.
- **PATCH**: Wording is clarified, examples are adjusted, or non-semantic
  refinements are made without changing what the principles require.

Every amendment MUST record its rationale in the Sync Impact Report at the
top of this document, and MUST update dependent artifacts (templates, guides,
and any documentation that references the changed rules) in the same change.
Any permanent architectural change to the product — a new layer, a
reorganized edge, a new class of capability, a change in how the platform
authorizes calls — obliges a review of this Constitution, whether or not the
change ultimately requires an amendment.

**Version**: 1.0.0 | **Ratified**: 2026-09-20 | **Last Amended**: 2026-09-20
