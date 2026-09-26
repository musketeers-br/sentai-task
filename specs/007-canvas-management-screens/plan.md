# Implementation Plan: Canvas Management Screens (frontend)

**Branch**: `007-canvas-management-screens` | **Date**: 2026-09-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-canvas-management-screens/spec.md`. This plan is
frontend only. Part A (Task catalog, US-1…US-4) is planned in full against `design/Catalog.dc.html`.
Part B (custom steps, US-5 and US-6) is planned architecturally, and its visual tasks are **blocked
until the prototype exists**.

## Summary

The existing SvelteKit canvas gains two things:

- **Task catalog screen.** It is reached from the top bar and is addressable through the page's
  query string (`?view=catalog&task=<id>`). The single prerendered page stays as it is, because the
  static file server has no SPA fallback (research R-1). The screen renders only the spec 006 API's
  values:
  - "unavailable" is shown with the platform's reason;
  - "destructiveness unknown" is shown as unknown;
  - SentaiTask origin links to `?flow=<id>`;
  - filters and counts come from the API;
  - suspend/resume is always followed by a re-read.
- **Declared custom steps in the flow editor.**
  - A *Custom* palette group keyed on the API's `executor`.
  - An inspector form generated from the API's parameter schema, with no local schema and no
    copied defaults.
  - Parameter errors shown verbatim. They appear on the field only when the finding carries a
    structured `parameter` (a backend dependency on spec 005); otherwise they are shown at step
    level.
  - The legacy `custom` class shown read-only.
  - The missing third destructive signal: a typed confirmation before dispatch.

Existing components are reused (TopBar, Palette, Inspector, StepNode, StatusBar, DispatchDialog,
the tokens and the state shapes). No second design system is introduced.

## Technical Context

**Language/Version**: TypeScript 5.9, Svelte 5 (runes), SvelteKit 2 (`adapter-static`, `prerender`, `ssr=false`)

**Primary Dependencies**: `@xyflow/svelte` (canvas, unchanged). Nothing new: no UI kit, no
DevExtreme, no router library.

**Storage**: none. Tokens are in memory (existing session); catalog data lives only while the screen is mounted

**Testing**: `vitest` (unit, pure functions and adapters, with fixtures taken from the 005/006
api-deltas); `@playwright/test` e2e against the container `http://localhost:52773/csp/sentai/`
(existing config, 1 worker)

**Target Platform**: desktop browsers (spec 002 assumption), served by `sentai.web.StaticFiles` at `/csp/sentai`

**Project Type**: web frontend (single prerendered page + client-side API)

**Performance Goals**: catalog first rows < 3 s and a filter update < 2 s with about 150 tasks
(SC-003). The API itself takes about 0.4 s (spec 006 R-2). Search is debounced 300 ms, and stale
responses are dropped by sequence number

**Constraints**: no backend change; no new endpoint; no background polling; no task
create/edit/delete/run-now; no History or WQM screens; the live-run screen ignores
`result`/`executedAs`; no test removed

**Scale/Scope**: 5 new components and 3 new pure modules; 8 existing files touched; unit 48 → ~81;
e2e 13 → 23

No NEEDS CLARIFICATION remains. R-1…R-7 are resolved in [research.md](research.md).

## Constitution Check

*GATE: checked before Phase 0 and again after Phase 1.*

| Principle | How the design complies | Status |
|---|---|---|
| **I Layered Architecture** | Components → view models (pure `src/lib/catalog/*.ts`, `src/lib/flow/*`) → `src/lib/api/client.ts`/`wire.ts`, the only modules that know HTTP and wire shapes. Components never call `fetch` or read wire keys. | ✅ |
| **II Closed Capability Set** | No field where a class name or a parameter key is typed: the legacy custom-class input is removed (FR-018). Parameter fields come only from the API schema, with names never typed (FR-013). An unknown parameter type is shown read-only, never as free text. Nothing is evaluated from input. | ✅ |
| **III Delegated Authorization** | Every call uses the operator's session token. Suspend/resume visibility follows `suspended` only, with no permission guess (the button shows, and the platform decides). Refusals show HTTP status plus the platform's text, or "no reason given", with `platformStatus` kept untouched. No action is replayed after re-sign-in. Nothing about permission is cached. | ✅ |
| **IV Errors as Values** | `ApiResult`/`ApiError` (existing) extended with `platformStatus`/`platformInfo`. Every screen state is a tagged union (`refused`, `notFound`, `actionError`, `unavailable`); no exception crosses a component. | ✅ |
| **V Verifiable Increments** | Tasks are sliced by user story, each with its e2e. Cross-spec sequencing is declared (BD-3: Part A e2e after 006; BD-4 and the prototype gate for Part B). | ✅ |
| **VI Technology Agnosticism** | Technology is named here only; the spec stays free of it. | ✅ |
| **FR-019 audit (no business logic in the browser)** | Local decisions found in the current code are listed in [research.md §Other findings](research.md#other-findings-code-audit-against-fr-019-fr-013-and-fr-018). **Changed**: local parameter schema/default (declared types), the custom-class input, and label derivation (API `label` preferred). **Kept with reason**: category display order (presentation); the `purge-audit-records` local field (BD-2, keeps e2e green); consequence copy (spec 002 presentation). Filtering and counting of the catalog is never done locally; sorting is display order only (R-3). | ✅ |
| **Handoff constraints** | No DevExtreme; no credentials in the repo, fixtures or evidence (e2e reads env vars; temporary users get IRIS-generated passwords); no confidential names; no AI. | ✅ |

**Post-design re-check**: unchanged, all ✅. There are no Complexity Tracking entries.

## Decisions

- **D-1 Routing (R-1).** One page, with the screen in the query (`view`, `task`), plus `flow`/`run`
  as today.
  - Navigation uses `goto(…, {keepFocus, noScroll})`, not shallow routing.
  - The screen is derived from `page.url`.
  - `syncUrl()` moves to `goto(…, {replaceState:true})`.
  - The editor instance is kept, so the open flow and unsaved edits survive switching screens.
- **D-2 Top bar.** `TopBar.svelte` gains nav tabs *Flows / Task catalog* (the active one is marked,
  as in the prototype). Flow actions (name, Save, Validate, Schedule, Run) render only on the Flows
  screen. Theme switch, user and Sign out stay on both. *History* and *WQM* are not rendered.
- **D-3 Catalog.**
  - The pure module `src/lib/catalog/catalog.ts` holds `fromWireCatalogTask`,
    `orderByNextRun`, `namespaceOptions`, `refusalText` and `statusLabel`.
  - The components are `CatalogScreen.svelte` (filter bar, table, footer),
    `CatalogDetail.svelte` (detail pane and actions) and `CatalogValue.svelte` (one field
    rendering value, unavailable or absent).
- **D-4 Namespaces (R-2)** come from the latest unfiltered page. **Sort (R-3)** is stable
  bucketed text order that never reformats a value.
- **D-5 Suspend/resume.** The button is disabled while pending. After any answer the item is
  re-read, and after success the list is re-read too (FR-011). There is no auto-retry after 401
  (R-5).
- **D-6 Declared steps.**
  - `fromWireStepTypes` maps `label`, `executor` and `parameters`.
  - *Custom* group = `executor === 'in-process'` plus the `custom` legacy entry (Clarifications
    Q1).
  - `ParameterForm.svelte` renders from `ParameterSpec[]`.
  - Defaults are placeholders, and the key is omitted until the operator sets it (R-7).
  - Findings are matched on the structured `parameter` only (R-4, BD-1).
- **D-7 Third destructive signal.** `DispatchDialog.svelte` gains one required typed field per
  destructive step and sends `confirmations[{stepId, typedName}]`. A 428 detail is shown verbatim.
  This closes a spec 002 FR-013 gap found by the audit. It becomes reachable once 005 makes
  `purge-task-history` available.
- **D-8 Legacy `custom`.** The inspector shows the class as read-only text with "not supported".
  The palette entry is disabled (`available:false` from the API).

## Spec deviations (to reflect at `/speckit-tasks`)

| Spec text | Finding | Plan |
|---|---|---|
| US-5.4 / FR-015 / SC-005: errors "shown on its field" | The findings carry no structured parameter (R-4) | Shown on the field only when `parameter` is present (BD-1 on 005); otherwise at step level, verbatim. SC-005's field part is gated on BD-1 |
| US-5.5 "Unchanged defaults are sent as the schema's default" | 005 applies the default when the key is absent | The key is omitted, the default shown as placeholder (R-7), and FR-016 is honoured |
| Design brief item 5 "the existing dialog" | There is no typed-confirmation input in the dialog today | The prototype must design it (T0 item 5); D-7 implements it |
| FR-002 "reached directly by address" | No path routes on the static server | Addressable by query string (R-1) |

## Project Structure

### Documentation (this feature)

```text
specs/007-canvas-management-screens/
├── spec.md
├── plan.md                        # this file
├── research.md                    # R-1…R-7, FR-019 audit
├── data-model.md                  # view models
├── contracts/api-consumption.md   # calls, per-status screen behaviour, BD-1…BD-4
├── quickstart.md                  # acceptance per story, SC-001…SC-008
├── checklists/requirements.md
├── evidence/                      # written by the quickstart
└── tasks.md                       # /speckit-tasks
```

### Source Code (frontend)

```text
frontend/src/
├── routes/+page.svelte                 # TOUCH: view from page.url; goto navigation; mounts CatalogScreen
├── lib/api/client.ts                   # TOUCH: catalog calls; ApiError.problem + platformStatus/platformInfo
├── lib/api/wire.ts                     # TOUCH: StepType label/executor/parameters
├── lib/catalog/catalog.ts              # NEW (pure): wire→view, orderByNextRun, namespaceOptions, refusalText, statusLabel
├── lib/catalog/CatalogScreen.svelte    # NEW: filter bar, table, footer, refused state
├── lib/catalog/CatalogDetail.svelte    # NEW: detail pane, origin link, recent runs, Suspend/Resume
├── lib/catalog/CatalogValue.svelte     # NEW: value | unavailable(reason) | absent
├── lib/shell/TopBar.svelte             # TOUCH: nav tabs; flow actions only on Flows
├── lib/flow/document.ts                # TOUCH: StepTypeInfo fields; createStep without copied defaults for declared types; label
├── lib/flow/params.ts                  # NEW (pure): ParameterSpec → field model, value coercion, findings by parameter
├── lib/inspector/ParameterForm.svelte  # NEW: generated form (blocked on prototype)
├── lib/inspector/Inspector.svelte      # TOUCH: use ParameterForm for declared types; legacy custom read-only
├── lib/palette/Palette.svelte          # TOUCH: Custom group by executor; label
└── lib/shell/DispatchDialog.svelte     # TOUCH: typed confirmations (D-7)

frontend/tests/
├── us7-catalog.spec.ts            # NEW  US-1 (+ routing/back)
├── us8-catalog-origin.spec.ts     # NEW  US-2
├── us9-catalog-filters.spec.ts    # NEW  US-3
├── us10-catalog-suspend.spec.ts   # NEW  US-4
├── us11-declared-steps.spec.ts    # NEW  US-5
├── us12-destructive-legacy.spec.ts# NEW  US-6
└── us13-management-theming.spec.ts# NEW  SC-008
```

**Structure Decision**: the existing single frontend package. The catalog concern lives in
`src/lib/catalog/`. Pure logic (wire mapping, ordering, refusal text, parameter model) sits in
`.ts` modules with unit tests, and components only render.

## Implementation Sequence (input to /speckit-tasks)

The rules:
- test first: e2e per story (SC-007), plus unit tests for the pure modules;
- `+page.svelte`, `TopBar.svelte` and `Inspector.svelte` are edited sequentially where they appear;
- `[P]` marks tasks that share no file.

| # | Task | Story / FR | Depends | Parallel |
|---|---|---|---|---|
| T0 | **Design (prerequisite for Part B, no code).** Produce the Part B prototype in the design tool, in the `System.dc.html` visual system, both themes, saved to `design/`. It shows: (1) the palette *Custom* group (2 available declared types, 1 unavailable, legacy `custom`); (2) a declared node, normal and destructive; (3) the parameter form with the 4 types, required marks, a default placeholder, description, one field in error **and** the step-level error variant (BD-1), and the "no parameters" variant; (4) legacy `custom` read-only; (5) the **new** typed-confirmation dialog (one field per destructive step, a 428 error state); (6) the status bar counting a parameter error. | Design brief | — | [P] with 1–5 |
| 1 | **Navigation and routing.** e2e first (`us7`): deep link, back/forward, reload, and the open flow with an unsaved edit kept. `TopBar` nav; `+page.svelte` view from `page.url`; `syncUrl` moves to `goto`. The catalog screen initially shows a list with name/namespace only. | FR-001, FR-002 | BD-3 for e2e | — |
| 2 | **List: columns, sort, unavailable, refusal.** Unit (`catalog.test.ts`): wire→view with the 006 fixtures (tasks 4 and 1000, and the partial task); `Value` value/unavailable/absent; `statusLabel`; `orderByNextRun` over R-3 buckets; `refusalText` (detail / errors / "no reason given"). e2e (`us7`): SC-001 comparison for every row, the refused state for an unprivileged operator. `client.ts` catalog list and `ApiError` extension; `CatalogScreen`, `CatalogValue`. | US-1, FR-003, FR-004, FR-007, FR-010 | 1 | — |
| 3 | **Filters and count.** Unit: `namespaceOptions` from an unfiltered page; query building (defaults omitted). e2e (`us9`): each filter, one combination, "N of M" equals the API. Debounce and sequence number. | US-3, FR-005, FR-011 (refresh) | 2 | — |
| 4 | **Detail, origin and link.** Unit: origin rendering model (`flowExists` true/false/absent); recentRuns absent vs `[]` vs list. e2e (`us7` details, `us8`): SC-001 for 3 details, SentaiTask marks for a scheduled 3-step flow, link to the flow in ≤ 2 clicks, deleted flow → "flow not found". `CatalogDetail`. | US-1.4–7, US-2, FR-006, FR-009 | 2 | [P] with 3 (different files: 3 touches `CatalogScreen` and `catalog.ts` filters, 4 touches `CatalogDetail` and `catalog.ts` origin; sequential if the same function block is edited) |
| 5 | **Suspend/resume.** Unit: action-state reducer (pending → ok / error + re-read). e2e (`us10`): suspend → SUSPENDED shown and confirmed by a fresh read; resume; button disabled while pending; 403 refusal shown verbatim. | US-4, FR-008, FR-011 | 4 | — |
| 6 | **[BLOCKED on T0] Custom group and labels.** Unit (`wire.test.ts`, `document.test.ts`): `label`/`executor`/`parameters` mapping; pre-005 catalog still maps; grouping. e2e (`us11`, part 1): *Custom* group equals the catalog's in-process entries plus legacy `custom` (disabled). `Palette`, `wire.ts`, `document.ts`. | US-5.1, FR-012 | T0, BD-4 | — |
| 7 | **[BLOCKED on T0] Parameter form and errors.** Unit (`params.test.ts`): spec → field (each of the 4 types, bounds, required, placeholder default); writes (coerce, clear removes the key); findings matched by `parameter` only, with a fixture **with** and **without** `parameter`; an unknown type becomes a read-only row. e2e (`us11`, part 2): exact fields for `storage-headroom-check`, "takes no parameters" for `db-size-report`, an out-of-range value shown verbatim at field or step level (recorded). `params.ts`, `ParameterForm`, `Inspector`. | US-5.2–5, FR-013–FR-016 | 6 | — |
| 8 | **[BLOCKED on T0] Destructive declared type, typed confirmation and legacy custom.** e2e (`us12`): `purge-task-history` shows the band and seal; dispatch asks for the typed value; a wrong value → 428 detail verbatim; the right value dispatches; a legacy `custom` flow shows as not supported with a read-only class and no input. `DispatchDialog`, `client.ts` dispatch body, `Inspector` (custom). | US-6, FR-017, FR-018 | 7 | — |
| 9 | **Theming parity and evidence.** e2e (`us13`): dark/light pairs of the catalog and the parameter form, with the 002 US-6 assertions. SC-003 timing with about 150 seeded tasks. Run the quickstart and record the evidence. README: the catalog screen, custom steps, BD-1…BD-4 status. | FR-020, SC-003, SC-008 | 5 (Part A); 8 (Part B pair) | — |

**Cut order if time runs short**:
1. Part B tasks 6–8 wait for the prototype and 005, without affecting Part A.
2. The Part B half of task 9 follows them.
3. Part A tasks 1, 2, 4 and 5 are never cut.
4. Task 3 (filters) can ship with search and state filters first and the namespace filter after.

**Expected test count**:

- **Unit: 48 → ~81 (+33).**

  | Area | Tests |
  |---|---|
  | catalog wire and view | 8 |
  | sort | 5 |
  | refusal and status | 4 |
  | filters and namespaces | 3 |
  | origin and recentRuns | 3 |
  | action reducer | 2 |
  | step-type wire and grouping | 3 |
  | params | 5 |

- **e2e: 13 → 23 (+10).**

  | Spec | Tests |
  |---|---|
  | `us7` | 2 |
  | `us8` | 1 |
  | `us9` | 1 |
  | `us10` | 2 |
  | `us11` | 2 |
  | `us12` | 1 |
  | `us13` | 1 |

- **Adjusted: 0 planned, 0 removed.** Two exceptions are possible:
  - If 005 lands first and moves `switch-journal` to available, the `us1` palette assertion is
    adjusted **by 005's own task 9**, not here.
  - If `stepLabel` preference for API `label` changes a visible title asserted by an existing e2e
    test, that assertion is adjusted to the API label in the same task, and the change is
    declared there.

## Risks

| Risk | Mitigation |
|---|---|
| 005/006 not deployed when 007 starts | Unit tests on api-delta fixtures; e2e gated per task (BD-3/BD-4); Part A and Part B are independent |
| `goto` to the same route remounts or reloads state in some SvelteKit version | Task 1's first e2e asserts that the unsaved edit survives a screen switch; fallback is a single `view` store synced to the URL by `replaceState`, and back handled through `popstate` |
| No structured `parameter` in findings (BD-1) | Step-level display, verbatim; SC-005's field part recorded as gated, never met by text parsing |
| Typed-confirmation UI is new (D-7) and touches dispatch | Covered by `us12`; existing `us4` dispatch tests (non-destructive flows) must stay green |
| Seeding about 150 tasks for SC-003 is slow | Schedule a few large integrity-check flows (one task per step) through the product API; delete in teardown; record the count |
| The API label changes existing visible titles | Declared in task 6; adjust only titles asserted by e2e, never remove tests |
