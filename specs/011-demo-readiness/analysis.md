# Specification Analysis Report: 011 Demo Readiness

Run: 2026-09-28, after `tasks.md`, over spec.md, plan.md, research.md, data-model.md,
quickstart.md and tasks.md, checked against the constitution (v1.0.0). Read-only pass. The
findings marked *fixed* were corrected in the artifacts in the same session.

| ID | Category | Severity | Location | Summary | Resolution |
|---|---|---|---|---|---|
| A1 | Coverage | MEDIUM | spec FR-012 / tasks | "Reset MUST NOT change the privileged accounts or other settings" had no test. | *fixed*: `TestResetLeavesSettingsAlone` (T010) and quickstart A item 7 re-checks `_SYSTEM:SYS` → 401 after the reset. |
| A2 | Inconsistency | LOW | plan D-9 vs tasks T016 | `Demo.Setup()` in the plan vs `Setup(1)` in the tasks. | *fixed*: the plan now requires the explicit `1`. |
| A3 | Coverage | LOW | spec FR-010 | A VM reboot is not tested, only `docker compose restart` (acceptance item 8). | Accepted: restart covers the persistence question (R-5). The reboot depends on Docker being enabled at boot, which the README documents. Checked once on the VM in T024. |
| A4 | Underspecification | LOW | research R-4 | The demo role's content is unknown until T001. | Accepted: T001 is a declared blocker of T014/T016, with a stop condition (`%Admin_Secure` or `%All` needed). |
| A5 | Constitution | — | reset deletes flows | The reset deletes flows, which the product itself cannot do. | Not a violation: it is a host action behind the demo marker, not a routed operation (II), and it decides no permission (III). Recorded in plan *Constitution re-check*. |
| A6 | Ambiguity | LOW | spec SC-006 | "checked at least twice a day" depends on the host's cron. | Accepted: plan D-16 gives the cron lines; T024 records them. |

## Coverage summary

| Requirement | Tasks |
|---|---|
| FR-001–FR-004 (README) | T019, T020, T021 |
| FR-005, FR-005a (stack, exposure) | T015, T016 (acceptance items 2–3) |
| FR-006 (secret) | T001, T014, T016 (items 1, 3) |
| FR-007 (demo account) | T001, T014 (item 4) |
| FR-008 (showcase) | T008, T009 (item 5) |
| FR-009 (hint) | T017, T018 |
| FR-010 (reboot) | T016 (item 8), T024 |
| FR-011–FR-014 (reset, status) | T010, T011, T012 (item 7) |
| FR-015–FR-018 (cancel notice) | T003–T006 |
| FR-019 (English) | T006, T018 |
| FR-020 (no masking) | hard rule; T004 clears the alert only in the test helper |

- Requirements: 21, all with at least one task. Tasks: 24, none unmapped (T002, T022–T024 are
  setup and polish).
- Critical issues: 0. Constitution conflicts: 0.
- Ready for implementation.
