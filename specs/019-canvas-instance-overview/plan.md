# Implementation Plan: Canvas Instance Overview — Every Contest Area at a Glance

**Branch**: `019-canvas-instance-overview` | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-canvas-instance-overview/spec.md` (clarified
2026-09-29, 2 questions + alignment with spec 018)

## Summary

A new *Overview* screen, the landing screen for an address that names nothing, shows spec 018's 11
area cards from one summary read; instance cards open a sortable, filterable detail view with
optional 10 s auto-refresh; report cards run their spec 013 report on demand into the run's own
`ResultPanel` and keep the last result in memory; report cards can become a scheduled one-step flow
through spec 018 and the existing `ScheduleDialog`. All logic sits in a pure view-model module;
components only render it. Details and the alternatives rejected are in [research.md](research.md).

## Technical Context

**Language/Version**: TypeScript 5.9 + Svelte 5 (SvelteKit static build served by IRIS).

**Primary Dependencies**: none new. Consumes spec 018's routes
([ui-contract](contracts/ui-contract.md)).

**Storage**: none (memory only; FR-018).

**Testing**: vitest `src/lib/overview/overview.test.ts` (wire → view, card states, headline lines,
sort/filter, card report kept across refresh, `screenOf` rules in `src/lib/shell/screen.test.ts`);
`npm run check`; Playwright `tests/us29-overview.spec.ts` against the baked bundle (publish first).

**Target Platform / Project Type**: as today — the canvas IRIS serves at `/csp/sentai/`.

**Performance Goals**: SC-001 all cards within 3 s (summary measured ≈ 0.6 s by spec 018).

**Constraints**: components never call `fetch`; no computed or thresholded values (FR-005); no
"CPU"/"memory"/"log" labels on their own (FR-006); nothing new in browser storage; UI English.

**Scale/Scope**: 1 view-model module (~250 lines) + tests, 4 components (Overview screen, card,
detail view, reading table), client methods, screen routing and top-bar tab, e2e helper default,
1 e2e spec (~8 cases).

## Constitution Check

| Principle | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | Components → `lib/overview/overview.ts` (pure) → `lib/api/client.ts`. No component imports `fetch` or wire types. | ✅ |
| **II Closed Capability Set** | The canvas only selects spec 018's fixed area ids and catalog step types; no path or code comes from the operator. | ✅ |
| **III Delegated Authorization** | Every value and refusal is the API's, shown verbatim; the canvas never hides a card or an action because of a guessed permission. Process controls appear only when the API offers them. | ✅ |
| **IV Errors as Values** | Card, reading and report states are tagged values; a refused refresh replaces stale rows. | ✅ |
| **V Verifiable Increments** | One increment per story, each with its vitest cases and an e2e case, starting from failing tests. | ✅ |
| **VI Technology Agnosticism** | Only in plan and research. | ✅ |

## Decisions

- **D-1 Addresses** (research R-1): `Screen` gains `overview`; no `view`, `flow` or `run` →
  Overview; `view=flows` is explicit; detail = `view=overview&area=<id>`.
- **D-2 e2e default** (R-2): `signIn(page, query = '?view=flows')`; no test removed.
- **D-3 Reuse** (R-4): `ResultPanel` and `ParameterForm` unchanged.
- **D-4 Schedule** (R-5): create through spec 018 → `?flow=<id>` → open `ScheduleDialog` only when
  validation has no errors.
- **D-5 Auto-refresh** (R-6): detail views, 10 s, off by default, paused while hidden.
- **D-6 Card report memory** (Q2): a `Map` owned by the Overview component; *Refresh* leaves it.
- **D-7 Process actions** (US5): rendered only if the API offers the routes (spec 018 T029 verdict);
  otherwise not built.

## Increments

| # | Story | First failing test | Then |
|---|---|---|---|
| 1 | US1 Overview at a glance | `overview.test.ts` (cards), `screen.test.ts` (Q1 rules); us29 A (11 cards), B (`SentaiDemo` refusal) | client, view model, screen, tab, e2e helper default |
| 2 | US2 detail views | `overview.test.ts` (sort/filter, refused refresh); us29 C, D (hidden tab) | detail view, table, auto-refresh |
| 3 | US3 reports on demand | `overview.test.ts` (card report kept); us29 E | report run, `ResultPanel`, `ParameterForm` |
| 4 | US4 schedule this check | us29 F | flow creation, navigation, dialog |
| 5 | US5 process actions (conditional) | us29 G | only if spec 018 shipped them |
| 6 | Polish | full e2e, `npm run check` | README, still, evidence |

## Project Structure

```text
specs/019-canvas-instance-overview/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md  tasks.md
├── contracts/ui-contract.md
├── checklists/requirements.md
└── evidence/

frontend/src/lib/overview/overview.ts (+ overview.test.ts)     # new
frontend/src/lib/overview/OverviewScreen.svelte                # new
frontend/src/lib/overview/AreaCard.svelte                      # new
frontend/src/lib/overview/ReadingView.svelte                   # new (table + auto-refresh)
frontend/src/lib/shell/screen.ts (+ screen.test.ts)            # overview screen, view=flows
frontend/src/lib/shell/TopBar.svelte                           # Overview tab
frontend/src/routes/+page.svelte                               # screen branch, schedule hand-off
frontend/src/lib/api/client.ts                                 # overview methods
frontend/tests/support.ts                                      # signIn default
frontend/tests/us29-overview.spec.ts                           # new
README.md, assets/media/stills/                                # contest table, still
```

**Structure Decision**: a new `lib/overview` domain, as `lib/runs` and `lib/targets` are.

## Complexity Tracking

No violations.

## Constitution re-check after Phase 1

Passing: the design shows the API's words and decides nothing the platform decides.
