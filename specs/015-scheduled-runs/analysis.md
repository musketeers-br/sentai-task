# Specification Analysis Report: 015 Scheduled Runs That Execute

Run: 2026-09-28, after `tasks.md`, over all artifacts, specs 008/012/013 (interactions), the current
code and the constitution (v1.0.0). Findings marked *fixed* were corrected in the same session.

| ID | Category | Severity | Location | Summary | Resolution |
|---|---|---|---|---|---|
| E1 | Constitution | CRITICAL (gated) | Principle III, Governance | Storing a credential for unattended runs changes how calls are authenticated; Governance makes a review mandatory. | Handled: the review concluded that a MINOR amendment (1.1.0) is needed, confining stored secrets to the platform's own store (plan item 7). T003 writes it and **requires the user's approval** before merge. It is not a violation once the amendment is merged. |
| E2 | Underspecification | HIGH | plan D-3 | Whether the wallet can authenticate the sign-in request without the product reading the password (`ApplyHTTP`) is unknown. | Gated by T001 with a documented fallback. T001 stops the feature if the wallet cannot restrict use by resource (the security premise). |
| E3 | Coverage | MEDIUM | spec US2-3 (*Renew credential*) | No test and no defined mechanics. | *fixed*: plan D-7 defines renew as a re-schedule with the same timing; T018 tests it. |
| E4 | Underspecification | MEDIUM | spec edge case "Clock and time zone" | The dialog must say times are the instance's, but it had no way to know the instance time. | *fixed*: `GET …/schedule` returns `instanceTime`, and the dialog shows it. |
| E5 | Cross-spec | MEDIUM | spec FR-009 vs spec 012 narrator | The scheduled dispatch message was not in 012's catalog. | *fixed*: T011 adds the variant (or writes the single entry itself if 012 is not merged). |
| E6 | Breaking change | MEDIUM | contract `POST /schedule` | The body changes shape. The only client is the canvas; README examples use the old body. | Accepted: 400 `SCHEDULE_FORMAT` names the new shape; T023 updates the README; `us3-schedule.spec.ts` is updated in T018. |
| E7 | Supersession | LOW | spec 003 FR-031 | "One task per step" is superseded. | Recorded in spec clarifications; T013 updates `TaskOrigin` and its spec 006 tests for the new name form. |
| E8 | Coverage | LOW | SC-006 (schedule in < 1 min) | Usability, not automated. | Accepted; checked by a team member during T024. |

## Coverage summary

| Requirement | Tasks |
|---|---|
| FR-001 | T004, T009, T018 |
| FR-002 | T005, T010, T018 |
| FR-003 | T001, T002, T022 |
| FR-004, FR-005, FR-006 | T005, T010, T012, T013 |
| FR-007 | T016, T017 |
| FR-008, FR-009, FR-011 | T006, T011, T016 |
| FR-010 | T014, T015 |
| FR-012–FR-014 | T012, T013, T018, T019 |
| FR-015 | T018, T019 |
| FR-016 | T020, T021 |
| FR-017 | T023 |
| FR-018 | T003 |

- Requirements: 18, all covered. Tasks: 25.
- Critical issues: 1, gated (E1: the amendment needs the user's approval before merge).
- Ready for implementation once T001 confirms the wallet premises.
