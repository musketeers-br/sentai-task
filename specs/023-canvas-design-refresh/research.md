# Research: Canvas Design Refresh

Probed on the dev stack (`sentai-task-iris-1`, IRIS 2026.2) and read from the repository on
2026-10-01. Re-based after `/speckit-analyze` (2026-10-01): every code reference below is
`origin/master` at `ab637c0`, which has specs 018 (Instance Overview API) and 019 (Canvas Instance
Overview) merged.

## R-1 — What already exists (the baseline the spec's deltas start from)

**Decision**: plan only the difference. Read from `origin/master` at `ab637c0`:

| Spec item | Already shipped | Delta in this spec |
|---|---|---|
| FR-011 status-bar counts | `formatSummary` prints "N steps · N joins · N destructive" (`lib/flow/document.ts`) | add snap and zoom |
| FR-012 zoom controls | `<Controls position="bottom-left">` in `FlowCanvas.svelte` | none; only the zoom value reaches the status bar |
| FR-008 template | spec 010 example flow, offered only with no saved flows (`EmptyCanvasInvitation.svelte`) | offer on every empty canvas |
| FR-016 order | `orderByNextRun` in `lib/catalog/catalog.ts` | footer |
| FR-017 recent runs | `CatalogDetail.svelte` "Recent runs" table | empty text; last five |
| FR-020 suspend/resume | two buttons → `POST /catalog/tasks/{id}/suspend` (spec 007), `reduceSuspendAction` state machine | one toggle + confirmation |
| FR-020a origin | `originMark` → "SentaiTask" mark | the inverse mark |
| Destructive consequence text | `consequence()` private to `Inspector.svelte` | move to a pure module, reuse in the catalog |
| FR-002 tabs incl. Overview | spec 019: Overview tab first, `screen.ts` default to `overview` | none |
| Overview screen | spec 019: 11 cards (`AreaCard`), reading view, *Run report* in the run viewer, *Schedule this check* (`lib/overview/*`) | bands above the cards (US3) |
| Top bar width | spec 019 squeezed `gap` (5 px), tab `padding` (6px 5px) and the name field (`min-width: 72px`) in `TopBar.svelte` to fit five tabs plus every flow action in 1440 px | moving the flow actions to FlowBar lets those squeezes be reverted (T016) |
| e2e entry to Flows | spec 019: `signIn()` uses `?view=flows`; `LANDING` for the landing screen (`tests/support.ts`) | none |

**Rationale**: the board was drawn against spec 002's design, not against today's app; several
"proposed" elements were built by specs 007, 010, 012 and 019 in the meantime.

## R-2 — Catalog counts and the unclassified filter

**Decision**: `GET /catalog/tasks` gains an additive `counts` object
`{suspended, destructive, unclassified}` computed over **all** tasks the list read enumerated,
before filtering, and a query parameter `unclassifiedOnly` (`0|1|true|false`, like
`destructiveOnly`) matching `destructiveUnknown = true`. Contract: [contracts/api-delta.md](contracts/api-delta.md).

**Rationale**: FR-015 requires counts from the API's answer, not from displayed rows; with a filter
on, the rows no longer contain the totals. `TaskService.List` already builds every task before
`TaskFilter.Matches`, so counting there costs no platform read. Measured: 16 tasks, 2 suspended,
2 destructive, 12 unclassified — the board's figures match the dev instance.

**Alternatives considered**: three extra filtered reads from the canvas (3× the per-task platform
reads, ≈ 3 × 33 calls); counting client-side on an unfiltered read (wrong as soon as a filter is
on, and a second read anyway).

## R-3 — Task detail fields the platform has

**Decision**: show the platform's `Description` (new `description` field in `TaskShape`, copied
verbatim from the single read); do **not** show WQM category or privilege.

**Rationale**: `GET /api/admin/v2/task?id=8` returns `Name, RunAsUser, TaskClass, NameSpace,
TimePeriod…, Description, Settings` — no WQM category, no privilege. A constant
"%Admin_Task:USE" would be the canvas stating an authorization outcome (Constitution III). The spec
was amended (FR-017).

**Alternatives considered**: rows always showing "—" (noise that suggests a missing read).

## R-4 — "Why this is destructive"

**Decision**: move `consequence(type, parameters)` from `Inspector.svelte` to
`lib/flow/consequence.ts` (pure, tested). The catalog detail finds the step type whose `className`
equals the task's `class` in the already-loaded registry (`GET /catalog/step-types`) and shows its
consequence with the type's default parameters, plus "classified from the step-type registry · not
editable here". A destructive task whose class is not in the registry (a SentaiTask flow task,
destructive through one of its steps, `TaskShape.ApplyDestructiveness` rule 3) shows "destructive
because flow N contains a destructive step".

**Rationale**: one source for the warning text in the inspector and the catalog; no text is
invented per task.

## R-5 — Landing screen and addresses

**Decision**: unchanged from spec 019 (its research R-2): `view` names a screen → it; else a `flow`
or `run` parameter → `flows`; else → `overview`. This spec only adds catalog filter parameters
(`filter`, `unclassifiedOnly`) to `?view=catalog` addresses for Overview's links.

**Rationale**: the static file server has no SPA fallback (spec 007 R-1), so the screen travels in
the query string; old `?flow=` links are shared in docs and evidence.

**Impact**: none — spec 019 already resolves the default screen this way in `screen.ts` and moved
every e2e entry to `?view=flows` through `signIn()`; this spec does not change either.

## R-6 — "Add to a flow" from the catalog

**Decision**: a pure `stepFromTask(task, registry)` returns either a step draft — the step type
matched by `className`, available, its declared defaults, and the task's `namespace` and
`runAsUser` in the step's own fields — or a reason (`no step type declares this class`,
`step type not supported in v1`, `class unavailable`). The page adds the draft to the open flow
with `editor.addStep` near the canvas centre, marks it dirty and navigates to Flows.

**Rationale**: the catalog response carries no task `Settings`, so the task's own parameter
values are unknown to the canvas; defaults are what dragging from the palette gives today. The
spec was amended (FR-018). Adding to the open flow never replaces it, so the spec 010 unsaved-changes
guard is not needed here.

## R-7 — Suspend/Resume toggle and confirmation

**Decision**: replace the two buttons with one switch (`role="switch"`, `aria-checked` = suspended)
that opens the existing `Modal.svelte` with the task name, the action and — when `origin` is
present — "the flow's scheduled runs stop until it is resumed". Confirm sends the spec 007 call;
the existing `reduceSuspendAction` keeps the pending/error/re-read behaviour. Cancel sends nothing.

**Rationale**: the typed gate (spec 007/us14) is for running destructive steps; suspending is
reversible. The state machine already re-reads item and list and shows the refusal verbatim.

## R-8 — Overview attention data sources

**Decision**: two reads in parallel, each failing alone; spec 019's summary read is reused, not
repeated:

| Band | Source |
|---|---|
| Needs attention — suspended, unclassified | `GET /catalog/tasks` (`counts`, items) |
| Needs attention — backup | spec 019's summary: the `activity` `AreaCardView` headline `lastBackup`, `uptime` |
| Next 24 hours | `GET /catalog/tasks` items' `nextRun`, `suspended`, `destructive`, `origin` |
| Unread summary | spec 019's `AreaCardView` states `refused`/`unreachable` + the catalog read's outcome |

**Rationale**: measured on the dev stack, the catalog read takes 0.10 s (16 tasks) and the summary
≈ 0.57 s (spec 018 R-3); running both concurrently keeps the bands well within SC-007's 3 s.

## R-9 — Reports stay as spec 019 built them

**Decision**: the board's "Run once" card and "returns its GUID" are not built; spec 019's *Run
report* (opens the run's report viewer; the card keeps the last report's counts) and *Schedule this
check* remain. FR-024 and FR-025 were withdrawn.

**Rationale**: 019's clarification decided this after the board was drawn, and it is tested; two
behaviours for one action would confuse operators.

## R-10 — Next 24 hours

**Decision** (corrected during implementation, 2026-10-02): a pure `scheduleStrip(items, now)`
buckets tasks whose `nextRun` falls in `[now, now + 24 h)` into half-hour slots, marks destructive
and suspended per slot, counts them, and returns the first `nextRun` after the window. `now` is the
**instance clock** — the summary's `readAt` (`2026-10-02 08:18:35`, the same clock and format as
`nextRun`) — never the browser's (the dev browser ran at UTC−3, the container at UTC). Without a
summary the strip says it cannot place the schedule. "Flow scheduled" = an item with `origin`
that is not suspended.

**Rationale**: no new read. Probed on the dev stack: a suspended task **keeps** its `nextRun`
(*Automatic Table Statistic Collection*, suspended, next run 02:00 — README: "A suspended task
keeps its nextRun"), so the board's "1 susp." in a slot is derived, not guessed; the first draft of
this decision assumed the opposite.

## R-11 — Palette collapse

**Decision**: a pure `collapseGroups(groups, limit = 3, expanded)` over the existing
`paletteGroups` output: per category, the count, the first `limit` available entries and
"Show N more"; all unavailable entries move to one trailing group "N types not supported in v1".
A search query expands everything (search must find collapsed entries, FR-013).

## R-12 — Accessibility check (SC-008)

**Decision**: add `@axe-core/playwright` as a dev dependency and one helper `expectNoSeriousA11y(page)`
used by the new e2e specs, in both themes; rules at `serious`/`critical` only.

**Alternatives considered**: manual checklist only (not repeatable); Lighthouse (whole-page score,
not per-screen violations).

## R-13 — Relation to specs 018 and 019

**Decision**: both merged (`origin/master`, 2026-10-01). Spec 019 owns the Overview screen, its
cards, reading view, on-demand reports and *Schedule this check*; spec 023 adds the unread summary,
Needs attention and Next 24 hours above them, extending 019's `OverviewScreen.svelte` and reading its
`AreaCardView` model without redefining it.

**Rationale**: the board predates 019; rebuilding 019's screen would discard tested work (vitest
236, us29-overview 7/7 at 019's close).
