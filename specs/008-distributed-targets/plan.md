# Implementation Plan: Distributed Targets (backend)

**Branch**: `008-distributed-targets` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-distributed-targets/spec.md` (Q1 = A, Q2 = A).
Backend only; the canvas is spec 009, which consumes [contracts/api-delta.md](contracts/api-delta.md).

## Summary

A step may carry `target`, the name of a registered instance of the platform. Platform-executed
steps (in v1: `integrity-check`) then make the same three management-API calls they make today —
start, poll, pause/cancel — against that instance's base address, with the operator's own
credential for it, obtained through a primary-side sign-in that keeps nothing. The run tracks the
remote step with the existing states and events, keeps its result on the primary (platform steps
now store their result, local and remote), and records `executedOn`. The registry of targets,
their live status and an online/offline flag are new product records and calls. Everything that
can go wrong with a target is a finding or a step failure reason, verbatim. The demo gains a
second IRIS container.

## Technical Context

**Language/Version**: ObjectScript on InterSystems IRIS 2026.2 (community), as specs 003–006.

**Primary Dependencies**: `%Net.HttpRequest` (existing `AdminApiClient`), `%SYSTEM.WorkMgr`
(existing), IRIS management API `/api/admin` on each target (spec 001 contract). Nothing new.

**Storage**: new persistent `sentai.model.Target`; new properties on `Step` and `StepRun`; run
target credentials in `^IRIS.Temp.sentaiTargetCred` (IRISTEMP, R-5).

**Testing**: `%UnitTest` via `zpm "test sentai-task -only"`, with `AdminApiDouble` extended to
answer per base address (one double per target); acceptance by curl against the compose stack
([quickstart.md](quickstart.md)); the frontend suites must stay green (SC-007).

**Target Platform**: Docker Compose: `iris` (SentaiTask) and `iris-target` (plain IRIS, nothing
installed).

**Project Type**: web service (REST API) in the existing module.

**Performance Goals**: status read < 3 s when reachable (SC-006); target calls time out after 10 s
(R-4).

**Constraints**: local behaviour and every existing test unchanged (FR-019); no stored credential
(FR-002); HTTPS for non-loopback targets unless the development allowance is set (FR-003).

**Scale/Scope**: 1 new persistent class, 1 new service class, ~7 new REST routes, 6+1 new codes,
~40 new unit test methods.

## Constitution Check

| Principle | How the design complies | Status |
|---|---|---|
| **I Layered Architecture** | `sentai.rest.Dispatcher` (edge) → `sentai.targets.TargetService` (registry, sign-in, status) and `WaveDispatcher`/`FlowValidator` (core) → `AdminApiClient` (infrastructure), which alone knows HTTP. The client gains an endpoint argument; the core never builds URLs itself. | ✅ |
| **II Closed Capability Set** | Only catalog types run remotely, gated by a declared `remoteCapable`; no method, class or code is taken from input; a target is only an address. The idea's "call arbitrary methods" is declined in spec and README. | ✅ |
| **III Delegated Authorization** | Every target call carries the operator's own credential for that target, obtained by the operator's own sign-in; no service account; the target's refusals are shown verbatim; nothing about permission is cached. Registry management is open to any signed-in operator (Q2), which grants nothing on a target. | ✅ |
| **IV Errors as Values** | Every failure is a finding, a Problem, or a step failure reason; transport errors now surface as values (R-4) instead of silent retries. A target down fails one step, never the run by itself. | ✅ |
| **V Verifiable Increments** | Tasks are sliced by observable behaviour (register+status, sign-in, remote step, refusals, down mid-run), each with unit tests and a quickstart section; T0 proofs precede the code that relies on them. | ✅ |
| **VI Technology Agnosticism** | Technology is named here, not in the spec. | ✅ |
| **Engineering standards** | TDD (tests first per task); YAGNI (no discovery, no load-based placement, local credential storage left as is); reproducibility (one `docker compose up` brings both instances). | ✅ |

No violations; no Complexity Tracking entries.

## Decisions

- **D-1 Client endpoint.** `AdminApiClient.Get/Post/Put/Delete` gain two trailing optional
  arguments: `baseUrl` (`""` = today's loopback host/port) and `ByRef transportError`. A new
  `ClassMethod Login(baseUrl, user, password, …)` sends Basic auth. Existing call sites are
  untouched (R-4, FR-019). `AdminApiDouble` routes by `baseUrl`.
- **D-2 Registry and service.** `sentai.model.Target` (data-model) and `sentai.targets.TargetService`
  (CRUD with the URL/HTTPS rule, online flag, sign-in, status). REST routes in `Dispatcher` only
  parse and shape.
- **D-3 Credentials.** Sign-in returns the pair and keeps nothing (R-6). Dispatch redeems each
  target refresh token, checks `sub`, stores the fresh pair in IRISTEMP (R-5); the run loop renews
  each after 40 s like E-1; `FinalizeRun` erases them.
- **D-4 Validation.** New rule block in `FlowValidator` for steps with `target`, in the spec's order
  (FR-009), with the R-8 split (warning without credential, full checks with it). The read-only
  probe is skipped for remote steps (it can only see the primary's filesystem).
- **D-5 Execution.** `StartStep` freezes `executedOn`/`targetBaseUrl` on the StepRun;
  `ExecuteStepAsync` starts the job on `targetBaseUrl` with the target token and sets `executedAs`
  to its `sub`; `PollInFlightSteps` polls `targetBaseUrl + adminJobId`, stores `result` on
  `Finished` (R-10, local too), records transport errors (R-12); `SweepTimeouts` covers remote
  steps.
- **D-6 Control.** `CancelStep`/`CancelRun`/`PauseStep` forward to the step's own instance
  (`async-result/cancel|pause?id=`) before the transition; for local steps this also closes spec
  003 follow-up T075.
- **D-7 Catalog.** `StepType.IsRemoteCapable(type)`; `ListStepTypes` adds `remoteCapable`.
- **D-8 Demo.** `Dockerfile_target` + `iris-target` service (R-13); `iris.script` sets the
  development allowance and creates the `SentaiTargets` SSL client configuration.
- **D-9 Docs.** README section "Implements DPI-I-588 (Distributed Work Manager)" and
  `docs/limitations.md` (FR-021).

## Spec deviations (to reflect at `/speckit-tasks`)

| Spec text | Finding | Plan |
|---|---|---|
| **D-1** FR-005 / US1: load as "queue lengths" | The proven categories read returns worker configuration, not queue length (R-2) | Categories as reported; `queueLength` only if T0 proves a read. Otherwise README states the platform does not report it |
| **D-2** FR-009: validation checks reachability and target answers | Validate has no target credential today (R-8) | Warning `TARGET_NOT_VERIFIED` without one; full checks with one; dispatch always full |
| **D-3** Assumption "the category must exist on the target" | The category governs the primary's queue (R-9) | Category checked on the primary as today |
| **D-4** New codes list | A target that answers 4xx to the reachability read is neither "unreachable" nor a credential problem | Additional code `TARGET_REFUSED` (message verbatim) |
| **D-5** FR-011 "in memory only" | A run spans processes; IRISTEMP is the non-persistent store they share (R-5) | `^IRIS.Temp.sentaiTargetCred`, erased at run end |

## Project Structure

### Documentation (this feature)

```text
specs/008-distributed-targets/
├── spec.md
├── plan.md                 # this file
├── research.md             # R-1…R-13
├── data-model.md
├── contracts/api-delta.md  # consumed by spec 009
├── quickstart.md           # acceptance by curl (a)–(f)
├── checklists/requirements.md
├── evidence/               # written by T0 and the quickstart
└── tasks.md                # /speckit-tasks
```

### Source Code (repository root)

```text
src/sentai/
├── model/Target.cls                  # NEW persistent registry
├── model/Step.cls                    # TOUCH: target
├── model/StepRun.cls                 # TOUCH: executedOn, targetBaseUrl
├── model/Flow.cls                    # TOUCH: SaveGraph/read carry target
├── targets/TargetService.cls         # NEW: CRUD, URL rule, online, sign-in, status
├── dispatch/AdminApiClient.cls       # TOUCH: baseUrl, transportError, Login
├── dispatch/WaveDispatcher.cls       # TOUCH: target credentials, remote start/poll/result, timeouts, forwarding
├── validation/FlowValidator.cls      # TOUCH: target rule block
├── registry/StepType.cls             # TOUCH: IsRemoteCapable
└── rest/Dispatcher.cls               # TOUCH: /targets routes, validate/dispatch bodies, executedOn
tests/sentai/unittest/
├── AdminApiDouble.cls                # TOUCH: per-baseUrl answers, transport-failure mode
├── targets/TargetServiceTest.cls     # NEW
├── targets/TargetRestTest.cls        # NEW
├── dispatch/RemoteStepRunTest.cls    # NEW
├── dispatch/TargetCredentialTest.cls # NEW
└── validation/TargetRuleTest.cls     # NEW
Dockerfile_target                     # NEW
docker-compose.yml                    # TOUCH: iris-target
iris.script                           # TOUCH: allowance, SSL config
README.md, docs/limitations.md        # TOUCH
```

**Structure Decision**: the existing single ObjectScript module; target concerns in a new
`sentai.targets` package, execution changes inside the existing dispatcher.

## Implementation Sequence (input to /speckit-tasks)

Each row: tests first; `zpm "test sentai-task -only"` green; frontend suites untouched and green.

| # | Task | Spec | Depends |
|---|---|---|---|
| T0 | **Proofs on a real second instance** (no product code): bring up `iris-target`; from the primary container prove login, refresh, info, wqm-categories (and look for a queue-length read), integrity-check start/poll/cancel; confirm `^IRIS.Temp.*` → IRISTEMP; record transport error texts for stopped/unknown host. Evidence in `evidence/t0-*.json` | R-1, R-2, R-4, R-5, R-13 | — |
| 1 | Demo environment: `Dockerfile_target`, compose service, `iris.script` allowance + SSL config | FR-020 | T0 |
| 2 | Client endpoint + transport errors (D-1); double per base URL. All existing tests unchanged | FR-019 | — |
| 3 | Registry: model, service, CRUD + online routes, URL/HTTPS rule | US1, FR-001…004, FR-023 | 2 |
| 4 | Sign-in and status | US1, FR-005, FR-006, FR-022 | 3 |
| 5 | Step `target`, catalog `remoteCapable`, validation block | US3, FR-007…009 | 3 |
| 6 | Dispatch with target credentials (missing, mismatch, redeem, store, erase) | US3, FR-010, FR-011 | 4, 5 |
| 7 | Remote start, poll, result, `executedOn`, renewal; platform results stored (R-10) | US2, FR-012…015, FR-018 | 6 |
| 8 | Cancel/pause forwarding (local and remote) | US2, FR-017 | 7 |
| 9 | Target down mid-run (timeout with transport error) | US3, FR-016 | 7 |
| 10 | Quickstart (a)–(f) on the compose stack with evidence; README DPI-I-588 section; limitations | FR-020, FR-021, SC-001…008 | 1, 8, 9 |

**Cut order if time runs short**: 8 (forwarding) then 9 (mid-run timeout) degrade to documented
limitations; 1–7 and 10 are the feature.

## Risks

| Risk | Mitigation |
|---|---|
| The target's integrity-check or async-result behaves differently when called from another host | T0 proves it before task 7 |
| The plain community image needs a password change before `/api/admin/login` works | `Dockerfile_target` unexpires passwords as the main image does (T0 checks) |
| `%Net.HttpRequest` default timeout makes an unreachable target slow to report | 10 s timeout on target calls (R-4) |
| Stored credentials leak through logs | Sign-in body never stored; quickstart (f) searches globals, `messages.log` and evidence |
| Tests starting real jobs | Every new unit test uses the double; real calls only in T0 and the quickstart |
| Time (deadline today) | Cut order above; spec 009 depends only on the contract, which is fixed here |
