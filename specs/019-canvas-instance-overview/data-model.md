# Data Model: Canvas Instance Overview (view models)

**Feature**: 019-canvas-instance-overview | **Date**: 2026-09-29

Everything here lives in memory in `src/lib/overview/overview.ts`; nothing is written to browser
storage (FR-018). Wire shapes are spec 018's data-model §2–§4.

## 1. AreaCardView

```ts
type CardState =
  | { kind: 'ok'; readAt: string; headline: Record<string, unknown> }
  | { kind: 'refused'; readAt: string; httpStatus: number; title: string; detail: string; platformStatus?: PlatformStatus }
  | { kind: 'unreachable'; readAt: string; detail: string };

interface AreaCardView {
  area: string;                 // spec 018 area id
  label: string;                // fixed display label per id (e.g. "Web sessions")
  group: 'instance' | 'report';
  state: CardState;
  stepType: string | null;      // "Schedule this check" only when set (FR-013)
  headlineLines: string[];      // formatted from headline, no arithmetic (FR-005)
  report: CardReport | null;    // clarification Q2, §3
}
```

Rules: order = the API's order; one entry's state never touches another; `headlineLines` formats
units and thousands separators only (`usedPercent` already comes from the API).

## 2. ReadingView (detail view)

```ts
interface ReadingView {
  area: string;
  readAt: string;
  columns: string[];            // API order
  rows: Record<string, unknown>[];
  computed: string[];           // marked "computed" in the header
  parts: Record<string, unknown> | null;
}
interface TableState { sortBy: string | null; descending: boolean; filter: string }
```

`visibleRows(view, state)` sorts (numbers numerically, strings case-insensitively, null last) and
filters (substring over every cell, case-insensitive). The "N rows / M shown" line comes from it.
Screen state: `{ kind: 'loading' } | { kind: 'list', view } | { kind: 'refused', … } | { kind:
'unreachable', detail }` — a refused refresh replaces the table (FR-009).

## 3. CardReport (clarification Q2)

```ts
interface CardReport {
  ranAt: string;
  state: 'completed' | 'failed';
  counts: { high: number; medium: number; info: number };
  failureReason: string;
  report: unknown;               // passed to ResultPanel as `result`
}
```

Held in a `Map<area, CardReport>` owned by the Overview screen component for the page's lifetime;
replaced when the report runs again; untouched by *Refresh*; gone on reload.

## 4. Addresses

| Address | Screen |
|---|---|
| no `view`, no `flow`, no `run` | Overview (Q1) |
| `?view=overview` | Overview |
| `?view=overview&area=<id>` | detail view of `<id>` (instance areas only; other ids → Overview with a notice) |
| `?view=flows` | Flows (empty canvas / open flow) |
| `?flow=…`, `?run=…` (no `view`) | Flows, as before |
| `?view=catalog|targets|runs` | as before |
