# Specification Analysis Report: 012 Run Log and Run History

Run: 2026-09-28, after `tasks.md`, over all artifacts of this feature, the constitution (v1.0.0)
and the current code. Findings marked *fixed* were corrected in the same session.

| ID | Category | Severity | Location | Summary | Resolution |
|---|---|---|---|---|---|
| B1 | Inconsistency with code | HIGH | data-model §2 "Re-run queued" | The row said `TransitionTo` writes it, but `RerunStep` saves the new attempt directly as `queued`, so no transition happens. | *fixed*: the row now names `WaveDispatcher.RerunStep`. |
| B2 | Inconsistency with code | MEDIUM | contracts SSE section | The first draft said `log-entry` SSE events would now flow; `StreamEvents` never emits them. | *fixed*: the contract says SSE is unchanged and T020 documents the gap. |
| B3 | Underspecification | MEDIUM | tasks T012 vs plan D-7 | The e2e paging used a `pageSize` address parameter the plan did not declare. | *fixed*: D-7 declares `pageSize` (1–200). |
| B4 | Coverage | MEDIUM | FR-011 | The UI side of a refused list had no test. | *fixed*: T012 routes a 403 and asserts the verbatim text. |
| B5 | Coverage | LOW | SC-002 | "Identifies the failing step in < 30 s" is a usability measure with no automated test. | Accepted: us24 asserts the facts it depends on (the failed line with the reason, in order). |
| B6 | Ambiguity | LOW | spec US1-7 | "newest visible" vs "time order". | Resolved in plan D-9: oldest first, auto-scroll to the newest while live unless the operator scrolled up. |

## Coverage summary

| Requirement | Tasks |
|---|---|
| FR-001, FR-002, FR-003 | T002, T003, T006, T007, T008 |
| FR-004 | T002 (narrator never throws), T007 (D-2) |
| FR-005 | T004, T005, T009 |
| FR-006–FR-010 | T010–T015 |
| FR-011 | T010 (403), T012 (verbatim in UI) |
| FR-012 | T004 |
| FR-013, FR-014 | T016, T017 |
| FR-015 | T009, T015, T017 |

- Requirements: 15, all covered. Tasks: 21.
- Critical issues: 0. Constitution conflicts: 0.
- Ready for implementation.
