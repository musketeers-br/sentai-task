# Specification Analysis Report: 014 Demo Media and Community Article

Run: 2026-09-28, after `tasks.md`, over all artifacts, specs 011–013 (dependencies) and the
constitution (v1.0.0). Findings marked *fixed* were corrected in the same session.

| ID | Category | Severity | Location | Summary | Resolution |
|---|---|---|---|---|---|
| D1 | Cross-spec inconsistency | HIGH | plan D-2 vs spec 011 | The recorder read a showcase fixture that spec 011 did not create (011 only created the example fixture), and relied on a `withReports` variant that 011 cannot know about. | *fixed*: spec 011 T008 now creates `showcase-flow.json` and tests the seed against it. 014 builds the report variant in its own code as a separate flow. |
| D2 | Terminology | LOW | spec FR-002 "lighter variant" vs plan "small" | Two names for one file; "light" also means the light theme. | Resolved: the file is `sentai-run-small.gif`; "light" is used only for the theme. |
| D3 | Coverage | MEDIUM | SC-004 (views double) | This outcome depends on the community, not only on the work. | Accepted as a measured outcome: T014 records it, and it is not a merge gate. |
| D4 | Constitution | — | captions overlay | Injecting UI into the product page could look like shipping unreviewed UI. | Not a violation: it is injected into the recorder's own browser session only (plan Constitution Check II). |
| D5 | Dependency | MEDIUM | T008, T013 | The final media and texts depend on 011–013 being merged, and the voting week is short. | Accepted: T003 adapts to what is merged, and T007 drafts with markers that block publishing (checker), so nothing unmerged is published. |

## Coverage summary

| Requirement | Tasks |
|---|---|
| FR-001–FR-006 | T001–T005 |
| FR-007–FR-010 | T006–T009 |
| FR-011, FR-012 | T011, T013 |
| FR-013 | T010 |
| FR-014 | T012, T013 |

- Requirements: 14, all covered. Tasks: 14. Critical issues: 0. Constitution conflicts: 0.
