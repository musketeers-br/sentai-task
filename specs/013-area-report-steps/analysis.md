# Specification Analysis Report: 013 Area Report Steps

Run: 2026-09-28, after `tasks.md`, over all artifacts, the constitution (v1.0.0) and the current
code. Findings marked *fixed* were corrected in the same session.

| ID | Category | Severity | Location | Summary | Resolution |
|---|---|---|---|---|---|
| C1 | Gap found in code | HIGH | spec FR-012 | While planning the result panel, the analysis found that the canvas shows **no** step result anywhere (`StepRunView` has no `result`), so spec 005's reports were only visible through the API. | *fixed*: FR-012 and US5 scenario 4 now require opening any stored result; T009 implements it for every type. |
| C2 | Coverage | MEDIUM | spec edge case "unless every read failed" | The all-reads-refused case of the security report had no test. | *fixed*: added to T010. |
| C3 | Underspecification | MEDIUM | FR-009, plan D-7 | What the platform's `SeriousAlerts` counts is unknown (179 on the dev instance while the monitor state was normal). The gate's meaning depends on it. | Accepted with a blocker: T001(c) establishes it before T008; research R-4 gives the decision for each outcome. |
| C4 | Underspecification | LOW | plan D-5 | Wallet field names are inferred, not observed (the dev wallet is empty). | Accepted: T001(a) records them before T016. |
| C5 | Coverage | LOW | SC-002 (8 parallel steps, local and target) | Not a single automated case; us27 covers local and target per type. | Accepted: quickstart 2 is the manual check, recorded in T018. |
| C6 | Constitution | — | new executor | A third executor could look like a new class of capability (Governance: "a new class of capability obliges a review"). | Reviewed: it only reads through the platform's API with the operator's credential (III) and runs fixed code chosen by type (II). No amendment needed; recorded in plan *Constitution re-check*. |

## Coverage summary

| Requirement | Tasks |
|---|---|
| FR-001 | T004, T007, T011, T014, T016 |
| FR-002, FR-003 | T003, T005, T010, T012, T013, T015 |
| FR-004 | T003 (FitResult protect) |
| FR-005 | T010, T015 (ResultSecrecyTest) |
| FR-006 | registry schemas (T004), rules in classes (T008, T011, T014, T016) |
| FR-007 | T010–T012 |
| FR-008 | T013–T014 |
| FR-009 | T005, T008, T017 |
| FR-010 | T015–T016 |
| FR-011, FR-012 | T006, T009 |
| FR-013 | T019 |

- Requirements: 13, all covered. Tasks: 21. Critical issues: 0. Constitution conflicts: 0.
- Ready for implementation after T001.
