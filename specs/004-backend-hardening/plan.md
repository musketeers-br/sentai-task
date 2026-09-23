# Implementation Plan: Backend Hardening — Reduce to Proven Truth

**Branch**: `004-backend-hardening` | **Date**: 2026-09-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-backend-hardening/spec.md`

## Summary

Surgical fixes to the spec 003 backend so it promises only what IRIS 2026.2 proved in T070:
an `available` flag in the step-type catalog blocks 6 unproven types on validate, dispatch,
schedule and rerun; category writes move to the validated `PUT …/wqm-category?name=` contract;
the nesting invariant treats `0` as unbounded; validation checks category existence against the
platform's list; and README/quickstart/handoff document what stays broken (60 s credential,
scheduled runs, unforwarded parameters). No new endpoints, no schema change, no feature.
Design decisions: [research.md](research.md).

## Technical Context

**Language/Version**: ObjectScript, InterSystems IRIS 2026.2 (Build 221U)

**Primary Dependencies**: `%CSP.REST`, `%Net.HttpRequest` (via `sentai.dispatch.AdminApiClient`), IRIS `/api/admin` management API

**Storage**: IRIS globals / persistent classes — **unchanged** (no class property added)

**Testing**: `%UnitTest` via `zpm "test sentai-task -v -only"`; `sentai.unittest.AdminApiDouble` stands in for the platform API

**Target Platform**: IRIS 2026.2 container `sentai-task-iris-1`, namespace `IRISAPP`

**Project Type**: web-service (REST backend for the spec 002 canvas)

**Performance Goals**: validation adds at most one platform category-list read per request

**Constraints**: no new endpoints; no flow JSON schema change; no removal of `/schedule`, confirmation or pause; all 86 existing tests pass (adjusted, none deleted); pure ObjectScript; ~8 tasks / ~3 h

**Scale/Scope**: 7 source classes touched, ~10 test classes touched/added, 3 docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|---|---|---|
| I. Layered Architecture | Availability lives in the registry (core data); rules in the validator; platform calls only through `AdminApiClient`/`CategoryService`. The validator gets the category list through `CategoryService`, not HTTP directly. | ✅ |
| II. Closed Capability Set | Change shrinks the executable set; `available` is compiled XData, not config or input. | ✅ |
| III. Delegated Authorization | Category existence comes from the platform, read with the operator's own credential per request; nothing cached across requests. 401s surface verbatim. | ✅ |
| IV. Errors as Values | New failures are `{stepId, code, message}` values / `%Status`; `CategoryService.List` gains a guard so a failed read returns `[]` instead of throwing. | ✅ |
| V. Verifiable Increments | Each task below ships with its failing test first and an observable REST outcome (quickstart (a)–(c)). | ✅ |
| VI. Technology Agnosticism | Tech choices stay in this plan; spec is contract-level. | ✅ |
| Eng. std: TDD | Every code task starts with a red test (task list). | ✅ |
| Eng. std: Separation of Concerns | `CheckConfirmations` extracted from `Dispatch` so the confirmation rule is testable on its own (R-007). | ✅ |

**Post-design re-check (after Phase 1)**: unchanged — all ✅. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/004-backend-hardening/
├── spec.md
├── plan.md              # this file
├── research.md          # R-001 … R-008
├── data-model.md        # catalog field, error codes, invariant table
├── quickstart.md        # real-instance validation guide ((a)–(c) + evidence notes)
├── contracts/
│   └── api-delta.md     # product API + platform API deltas
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
src/sentai/
├── registry/StepType.cls          # + "available" in XData, + IsAvailable()          (FR-001)
├── validation/FlowValidator.cls   # + availability rule, + category rule,
│                                  #   Validate/ValidateForSchedule(flowId, bearerToken="")  (FR-002, FR-006)
├── dispatch/WaveDispatcher.cls    # Dispatch(..., bearerToken=""), + CheckConfirmations(),
│                                  #   RerunStep availability guard                   (FR-002)
├── dispatch/AdminApiClient.cls    # + Put()                                          (FR-004)
├── wqm/CategoryService.cls        # Write → PUT wqm-category?name=; List guard       (FR-004, FR-006)
├── model/Category.cls             # SatisfiesInvariant: 0 = unbounded               (FR-005)
└── rest/Dispatcher.cls            # pass CurrentToken() to Validate/ValidateForSchedule/Dispatch

tests/sentai/unittest/
├── AdminApiDouble.cls             # + Put() recording ^sentaiTestDouble("put", path)
├── SentaiTestCase.cls             # + SupportedGraph(); script GET wqm-categories (Default, SQL, Utility, SENTAI.NIGHT)
├── registry/StepTypeTest.cls      # available per type
├── rest/StepTypeCatalogTest.cls   # response carries available
├── validation/StepAvailabilityRuleTest.cls   # NEW
├── validation/CategoryExistenceRuleTest.cls  # NEW
├── validation/CategoryInvariantTest.cls      # zero-as-unbounded rows
├── validation/WqmInvariantRuleTest.cls       # built-in Default passes
├── model/CategoryTest.cls, rest/WqmCategoryEndpointTest.cls  # PUT contract
├── dispatch/RerunControlTest.cls  # rerun refused for unavailable type
└── rest/{Validate,Dispatch,Schedule}EndpointTest.cls, validation/DestructiveSchedulingRuleTest.cls  # fixture moves

README.md                                          # + Known limitations (v1)
specs/003-backend-objectscript/quickstart.md       # "superseded by 004" banner
specs/003-backend-objectscript/HANDOFF.md          # + Resolution by spec 004
```

**Structure Decision**: existing single-project IRIS layout (`src/sentai`, `tests/sentai/unittest`);
no new packages.

## Implementation Sequence (input to /speckit-tasks)

Order is dependency-driven; each code task is test-first. Estimates sum to ~3 h.

| # | Task | FR | Depends | Est. |
|---|---|---|---|---|
| T001 | **Test scaffolding**: `AdminApiDouble.Put`; `SentaiTestCase` scripts `GET /api/admin/v2/wqm-categories` (Default/SQL/Utility with `MaxWorkers=0, MaxTotalWorkers=0`, + `SENTAI.NIGHT`) and adds `SupportedGraph()` (01, 02 `integrity-check` roots → 03 `integrity-check` join, all `Default`). Suite still green. | — | — | 20 m |
| T002 | **Registry `available`** (absorbs PROMPTS T007): XData field + `IsAvailable()`. Red first: `StepTypeTest` asserts the 7 values; `StepTypeCatalogTest` asserts the field in `GET /catalog/step-types`. | 001 | — | 15 m |
| T003 | **Availability rule + rerun guard**: `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` in `Validate()` (else-branch of `IsKnownType`); guard at top of `WaveDispatcher.RerunStep`. Extract `CheckConfirmations()`. Red first: new `StepAvailabilityRuleTest` (single unsupported, mixed flow, unknown type → only `UNKNOWN_STEP_TYPE`, custom w/o class → both errors), `RerunControlTest` case. | 002, 003 | T002 | 35 m |
| T004 | **Zero is unbounded**: `Category.SatisfiesInvariant`. Red first: `CategoryInvariantTest` rows from [data-model.md](data-model.md); `WqmInvariantRuleTest` flow on mirrored `Default` has no `WQM_INVARIANT_VIOLATED`. | 005 | — | 15 m |
| T005 | **WQM write contract**: `AdminApiClient.Put`; `CategoryService.Write` → `PUT /api/admin/v2/wqm-category?name=` with typed body without `Name`. Red first: test asserts recorded PUT URL/body and **no** POST to `wqm-categories/<name>`; update `CategoryTest`, `WqmCategoryEndpointTest` scripts. | 004 | T001 | 20 m |
| T006 | **Category existence**: `Validate(flowId, bearerToken="")`, `ValidateForSchedule(flowId, bearerToken="")`, `Dispatch(..., bearerToken="")`; REST passes `CurrentToken()`; `CategoryService.List` guard. Red first: new `CategoryExistenceRuleTest` (step category missing, flow default `SENTAI.DEFAULT` missing, list call 401 → fail closed, empty token → rule skipped). | 006 | T001 | 35 m |
| T007 | **Realign existing tests** to the new truth (FR-008): tests asserting `errors: []`/202/201 on the canonical flow move to `SupportedGraph()`; confirmation tests call `CheckConfirmations()`; `DestructiveSchedulingRuleTest` asserts presence (not exclusivity) of `DESTRUCTIVE_NOT_SCHEDULABLE`. Full suite green; none deleted; record the final count. | 008 | T002–T006 | 30 m |
| T008 | **Docs + real-instance proof**: README "Known limitations (v1)"; 003 quickstart banner; 003 HANDOFF "Resolution by spec 004"; execute [quickstart.md](quickstart.md) (a)–(c) on the instance, record evidence. | 007 | T007 | 30 m |

Parallelizable after T001: T002, T004, T005 (disjoint files). T003 needs T002; T006 touches
`FlowValidator` like T003 — run them one after the other.

## Risks

| Risk | Mitigation |
|---|---|
| Existing tests rely on the double's default `{}` for GET categories → `List` throws | T001 scripts the response in `SentaiTestCase`; T006 guards `List` |
| Tests calling `Validate(id)` with no token silently skip the category rule | `CategoryExistenceRuleTest` passes a token explicitly; the REST tests go through `CurrentToken()` |
| Real `PUT` rejects a full body | Evidence 10a proves a partial body; if the full body is rejected, T008 records it and the write sends only the changed fields |

## Complexity Tracking

None — no constitution violations.
