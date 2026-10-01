# Research: Canvas Instance Overview

**Feature**: 019-canvas-instance-overview | **Date**: 2026-09-29

Read against the frontend on `master` after spec 017 (the 018 worktree after its merge of
`origin/master`, 2026-09-29). The backend contract is
[spec 018's api-delta](../018-instance-overview-api/contracts/api-delta.md) and data model.

## R-1 — How screens are addressed today, and how *Overview* joins them

**Decision**: `Screen` gains `'overview'`. `screenOf(url)`:
`view=overview|catalog|targets|runs|flows` → that screen; no `view` **and** no `flow` or `run` →
`'overview'` (clarification Q1); no `view` with `flow` or `run` → `'flows'` (every deep link of
specs 007–015 keeps its meaning). `urlForScreen(url, 'flows')` now writes `view=flows` instead of
deleting `view`, so *Flows* stays reachable after the landing screen changed. A detail view is
`view=overview&area=<id>`.

**Rationale**: `src/lib/shell/screen.ts` keeps the screen in the query string because the static
file server has no SPA fallback (spec 007 R-1); the new rule is the smallest change that keeps all
old addresses meaningful (SC-007).

**Alternatives considered**: a new path (`/overview`) — impossible without an SPA fallback.

## R-2 — What the e2e suite assumes after sign-in

**Decision**: `frontend/tests/support.ts` `signIn(page, query = '')` waits for the palette heading
`STEP TYPES`, i.e. assumes the flow editor. Its default becomes `query = '?view=flows'`; a query
that already names a screen, flow or run is passed unchanged. The 59 `signIn(page…)` calls across
the specs keep working; `us20-example-flow` and `us21-getting-started` (which read the empty
canvas) are checked explicitly and adjusted only if they sign in without a query. No test is
removed (SC-007).

## R-3 — The view-model and client pattern to follow

**Decision**: `src/lib/overview/overview.ts` (pure: wire → view, card states, sort/filter, the
in-memory report per card) with `overview.test.ts`; `api.overview*` methods in
`src/lib/api/client.ts` returning `ApiResult<T>`; components never `fetch`. The card and reading
states follow `src/lib/targets/targets.ts`: `{ kind: 'ok' | 'refused' | 'unreachable', readAt, … }`
with the platform's words verbatim.

**Rationale**: AGENTS.md layering (components → `lib/<domain>/*.ts` → `lib/api/client.ts`) and the
spec 009 precedent for per-item outcomes.

## R-4 — Reusing the run's report viewer and the inspector's form

**Decision**: the on-demand report opens in `src/lib/run/ResultPanel.svelte` unchanged
(`{stepId, name, result, onclose}` — `stepId` = the area id, `name` = the catalog label, `result` =
`OnDemandReport.report`), so findings order and labels are identical to a run (SC-005).
Parameters use `src/lib/inspector/ParameterForm.svelte` (`{specs, parameters, findings,
onchange}`), with `specs` from the step-type catalog already loaded by the page, and the 422
`PARAM_*` findings mapped to `findings` as the inspector does.

## R-5 — Scheduling from a card

**Decision**: *Schedule this check* calls `POST /overview/areas/{area}/flow`, then navigates to
`?flow=<id>` (the Flows screen opens the flow through the existing loader) and sets the page's
`scheduling` flag so `ScheduleDialog` (`{editor, open}`) opens over the loaded flow — only when
the returned `validation` has no errors (FR-014). Otherwise the flow opens with its findings on the
node, as any validated flow.

**Rationale**: `ScheduleDialog` needs the `FlowEditor`, which lives on the Flows screen; opening it
anywhere else would duplicate the editor.

## R-6 — Auto-refresh

**Decision**: detail views only, off by default, every **10 s**, paused while
`document.visibilityState !== 'visible'` (a `visibilitychange` listener), one request in flight at
a time. *Overview* has manual *Refresh* only.

**Rationale**: the slowest measured reading is 158 ms (spec 018 R-1); 10 s is live enough for a
process list and cheap for the platform. The access token lives 60 s and the session renews it on
its own (spec 010), so auto-refresh adds no auth logic.

## R-7 — Large tables

**Decision**: plain `<table>` with client-side sort and text filter over all rows; no
virtualisation. 66 locks and 65 processes were measured; a sort of a few thousand rows is
instant, and the edge case asks only that no row be dropped silently — the table shows
"N rows" (and "M shown" when filtered).

## R-8 — Evidence and naming

**Decision**: e2e spec `frontend/tests/us29-overview.spec.ts`; evidence written to
`specs/019-canvas-instance-overview/evidence/`; the temporary operator for SC-003 is created with the
`SentaiDemo` role and removed by the test (spec 018 SC-003 wording).
