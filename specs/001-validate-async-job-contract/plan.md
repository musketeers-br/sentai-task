# Implementation Plan: validate-async-job-contract

**Branch**: `001-validate-async-job-contract` | **Date**: 2026-09-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-validate-async-job-contract/spec.md`

## Summary

A single Bash script probes the InterSystems IRIS Community management API
through its published container port, executes eleven predeclared calls in a
fixed order, captures one redacted evidence file per interaction, writes a
compatibility statement recording the exact platform version and image
digest, and records a written execution-model decision. Redaction happens in
the capture path — an unredacted file is never written to disk. The script
is rerun-safe: it cancels any job it left running and archives prior
evidence before overwriting it.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default) / Bash 4+ (Linux). No
shebang-pinned interpreter beyond `/bin/bash` or `/usr/bin/env bash`.

**Primary Dependencies**: `curl`, `jq`. Both are prerequisites the operator
installs; the script MUST detect their absence and refuse to start with a
clear message. No test framework, no build step, no other runtime dependency.

**Storage**: Filesystem only. Evidence files under
`specs/001-validate-async-job-contract/evidence/`; the compatibility
statement and execution-model decision at the feature directory root. No
database, no product-level persistence.

**Testing**: **Constitution exemption granted.** See the Constitution Check
below. This spike's deliverable is committed evidence, not user-observable
behavior; the automated-test requirement of Principle V does not apply, and
the review gate is human inspection of the committed artifacts.

**Target Platform**: InterSystems IRIS, Community Edition, run as a
container (Linux amd64 or arm64). Reached from the host at the container's
published HTTP port. The compatibility statement records the exact version
and the image's SHA256 digest.

**Project Type**: Spike / probe script. Not a product feature. Not a
library. Produces evidence artifacts that downstream features consume as
contract; produces no compiled or packaged deliverable.

**Performance Goals**: N/A. A single run captures eleven interactions; total
wall-clock is bounded by the async-job polling window in call (7).

**Constraints**:
- Redaction is in the capture path. An unredacted file MUST NOT exist on
  disk at any point, including partially-written temp files.
- Every request that carries a session token MUST have its `Authorization`
  header stripped from the captured evidence before the file is closed.
- The script MUST NOT leave a job running. Before exit — success or failure
  — any accepted-for-processing job identifier it holds MUST have been
  cancelled or observed to have settled.
- Second and later runs MUST NOT silently overwrite prior evidence. Prior
  evidence is moved to `evidence/.archive/<UTC-timestamp>/` and the
  compatibility statement records the replacement.
- Async polling MUST use a fixed interval and a bounded timeout, both named
  in the compatibility statement.
- The repository is public; the script's own source MUST NOT contain
  credentials.

**Scale/Scope**: One-shot script. Eleven captured interactions per run. One
compatibility statement, one execution-model decision, and one operator per
run.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.0.0:

- **I. Layered Architecture** — **Pass, N/A at product scope.** This spike
  produces evidence, not product code. It does not introduce a presentation
  layer, an application core, or an infrastructure abstraction to constrain.
  The script itself is a thin infrastructure probe with no domain logic.
- **II. Closed Capability Set** — **Pass.** The script performs a fixed,
  enumerated list of eleven calls (documented in `contracts/probe-plan.md`).
  It evaluates no input as code and constructs no request from user-supplied
  strings; the operator supplies credentials and a base URL only.
- **III. Delegated Authorization** — **Pass.** The script relies on the
  platform's authentication and authorization; a failed login stops the run
  and the platform's reply is captured verbatim (post-redaction) as
  evidence. No local permission model is introduced.
- **IV. Errors as Values** — **Pass.** Every capture records the response
  as-is, including non-2xx status codes and error bodies. A denied or failed
  call is a valid recorded outcome for its question, not a script abort;
  the script aborts only on unrecoverable infrastructure failure (missing
  `curl`, unreachable host, unauthenticated session).
- **V. Verifiable Increments** — **Exempt.** This spike's deliverable is
  committed evidence, not user-observable behavior; there is no automated
  test that could prove the evidence is right, because the evidence itself
  is the truth being captured. The exemption is granted for this feature
  only. Review is human inspection against the acceptance scenarios in
  [spec.md](spec.md); the criteria are recorded on the checklist at
  [checklists/requirements.md](checklists/requirements.md). Every feature
  that consumes this spike's evidence returns to the ordinary Principle V
  requirement.
- **VI. Technology Agnosticism** — **Pass.** The Plan names Bash, `curl`,
  and `jq`; the [spec.md](spec.md) does not. Downstream features are not
  forced to use these tools — they consume the evidence, not the probe.

**Result**: Constitution Check passes with one recorded exemption
(Principle V, scoped to this feature).

## Project Structure

### Documentation (this feature)

```text
specs/001-validate-async-job-contract/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output — the shape of an Evidence File
├── quickstart.md        # Phase 1 output — how to run the spike
├── contracts/           # Phase 1 output
│   ├── script-cli.md    # Operator-facing contract of run-spike.sh
│   ├── probe-plan.md    # The eleven calls, in order, with expected shapes
│   └── evidence-envelope.md  # The internal shape of one evidence file
├── checklists/
│   └── requirements.md  # Spec quality checklist (already written)
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
scripts/
└── validate-async-job-contract/
    ├── run-spike.sh              # Entry point
    └── lib/
        ├── redact.sh             # Redaction helpers (in-capture-path)
        ├── capture.sh            # curl invocation + envelope writer
        ├── auth.sh               # login / refresh / logout
        ├── probes.sh             # The eleven ordered probe functions
        └── cleanup.sh            # Cancel-any-outstanding-job + archive-prior
```

**Structure Decision**: One script per operator command, backed by a small
library of sourced helpers under `scripts/validate-async-job-contract/lib/`.
Everything the script writes lives under `specs/001-validate-async-job-contract/`.
No product-level `src/`, `tests/`, or package layout is introduced; this
spike is not a product feature and creating them now would violate YAGNI.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle V exemption (no automated tests) | The deliverable is committed evidence, not user-observable behavior; the evidence itself is the truth being captured, so an automated test would be tautological. | A shell-level test of the capture path (redaction, envelope structure) was considered but rejected: it protects only the script's internal contract, not the answers the spike must produce, and would introduce a test framework this spike is explicitly forbidden from taking on. |
